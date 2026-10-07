import Foundation
import ManagedSettings
import DeviceActivity

/// Blocks a profile's apps for the rest of the day once they've been used
/// for `minutes` in total.
struct DailyLimit: Identifiable, Codable, Equatable {
    var id = UUID()
    var profileID: UUID
    var minutes = 30
    var isEnabled = true
}

final class BlockRulesManager: ObservableObject {
    @Published private(set) var schedules: [BlockSchedule] = []
    @Published private(set) var limits: [DailyLimit] = []
    /// Rules iOS refused to schedule, e.g. past its limit on monitored activities.
    @Published private(set) var failedRuleIDs: Set<UUID> = []

    private let schedulesKey = "blockSchedules"
    private let limitsKey = "dailyLimits"
    private let signaturesKey = "registeredRuleSignatures"

    init() {
        schedules = load(schedulesKey)
        limits = load(limitsKey)
        removeLegacySettings()
    }

    /// Earlier builds shielded schedules through their own stores and had a
    /// Strict Mode that stopped every app from being deleted. Undo both once.
    private func removeLegacySettings() {
        let key = "removedLegacyRuleSettings"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        ManagedSettingsStore().application.denyAppRemoval = nil
        for schedule in schedules {
            ManagedSettingsStore.forRule(schedule.id).clearAllSettings()
        }
        for limit in limits {
            ManagedSettingsStore.forRule(limit.id).application.denyAppRemoval = nil
        }
        GooseShared.defaults.removeObject(forKey: "strictMode")
        UserDefaults.standard.set(true, forKey: key)
    }

    // MARK: Status

    func activeSchedules(at date: Date = Date()) -> [BlockSchedule] {
        schedules.filter { $0.isActive(at: date) }
    }

    /// Reached today and still blocking, i.e. not unlocked with a tag since.
    func isReachedToday(_ limit: DailyLimit) -> Bool {
        guard limit.isEnabled, let reached = GooseShared.limitReachedDate(limit.id),
              Calendar.current.isDateInToday(reached) else { return false }
        return !isLiftedToday(limit)
    }

    func isLiftedToday(_ limit: DailyLimit) -> Bool {
        guard let reached = GooseShared.limitReachedDate(limit.id),
              let lifted = GooseShared.limitLiftedDate(limit.id) else { return false }
        return Calendar.current.isDateInToday(lifted) && lifted >= reached
    }

    /// Tag or QR profiles need a scan to unlock a reached limit early; the
    /// others just confirm, since they chose not to be gated.
    func needsKeyToLift(_ limit: DailyLimit, profiles: [Profile]) -> Bool {
        profiles.first { $0.id == limit.profileID }?.unlockMethod == .key
    }

    /// Unblocks a reached limit's apps for the rest of the day. It starts
    /// counting again at midnight.
    func liftForToday(_ limit: DailyLimit) {
        ManagedSettingsStore.forRule(limit.id).clearAllSettings()
        GooseShared.setLimitLiftedDate(Date(), for: limit.id)
        // Keep the widget on any other limit that's still reached.
        let stillReached = reachedLimits().first
        GooseShared.setReachedLimitName(stillReached.flatMap { GooseShared.rules[$0.id]?.profileName })
        GooseShared.reloadSurfaces()
        objectWillChange.send()
    }

    func reachedLimits() -> [DailyLimit] {
        limits.filter(isReachedToday)
    }

    /// A reached limit can't be changed until tomorrow; otherwise editing it
    /// would be an easy way out. Schedules lock like the lock button does, so
    /// they unlock the normal way and can always be edited.
    func isLocked(_ limit: DailyLimit) -> Bool { isReachedToday(limit) }

    func isProfileInUseByActiveRule(_ profileID: UUID) -> Bool {
        reachedLimits().contains { $0.profileID == profileID }
    }

    // MARK: Editing

    func save(_ schedule: BlockSchedule, profiles: [Profile]) {
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) {
            keepLockUntilRunEnds(schedules[index])
            schedules[index] = schedule
        } else {
            schedules.append(schedule)
        }
        persist()
        sync(profiles: profiles)
    }

    func delete(_ schedule: BlockSchedule, profiles: [Profile]) {
        keepLockUntilRunEnds(schedule)
        schedules.removeAll { $0.id == schedule.id }
        persist()
        sync(profiles: profiles)
    }

    /// Editing, turning off or deleting the schedule that has you locked keeps
    /// you locked until that run would have ended, then unlocks on time. It
    /// can't be used as a way out, and doesn't leave the lock without an end.
    private func keepLockUntilRunEnds(_ schedule: BlockSchedule) {
        guard GooseShared.isBlocking, GooseShared.lockingScheduleID == schedule.id,
              let end = schedule.activeEnd(at: Date()) else { return }
        GooseShared.lockingScheduleID = nil
        GooseShared.blockEndDate = end
        AppBlocker.scheduleLockEnd(at: end)
    }

    func save(_ limit: DailyLimit, profiles: [Profile]) {
        if let index = limits.firstIndex(where: { $0.id == limit.id }) {
            guard !isLocked(limits[index]) else { return }
            limits[index] = limit
        } else {
            limits.append(limit)
        }
        persist()
        sync(profiles: profiles)
    }

    func delete(_ limit: DailyLimit, profiles: [Profile]) {
        guard !isLocked(limit) else { return }
        limits.removeAll { $0.id == limit.id }
        persist()
        sync(profiles: profiles)
    }

    // MARK: Sync

    /// Copies each rule's apps into the App Group for the monitor, and
    /// registers with DeviceActivity only what changed. Re-registering a limit
    /// restarts its count for the day, so unchanged ones are left alone.
    func sync(profiles: [Profile]) {
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        // Rules whose profile was deleted go too, unless they're mid-block.
        let orphanedSchedules = schedules.filter { profilesByID[$0.profileID] == nil }
        let orphanedLimits = limits.filter { profilesByID[$0.profileID] == nil && !isLocked($0) }
        if !orphanedSchedules.isEmpty || !orphanedLimits.isEmpty {
            schedules.removeAll { s in orphanedSchedules.contains { $0.id == s.id } }
            limits.removeAll { l in orphanedLimits.contains { $0.id == l.id } }
            persist()
        }

        var rules = GooseShared.rules
        var signatures: [String: String] = load(signaturesKey, default: [:])
        let center = DeviceActivityCenter()
        var liveIDs = Set<UUID>()

        for schedule in schedules {
            liveIDs.insert(schedule.id)
            if let profile = profilesByID[schedule.profileID] {
                rules[schedule.id] = rule(id: schedule.id, name: schedule.name, profile: profile, schedule: schedule)
            }
            // Timing is what DeviceActivity knows about; the apps are read from
            // the App Group copy whenever the schedule starts.
            let signature = Self.signature(schedule)
            if signatures[schedule.id.uuidString] != signature {
                center.stopMonitoring(Self.activityNames(for: schedule.id))
                var registered = true
                if schedule.isEnabled, rules[schedule.id].map(Self.hasApps) == true {
                    registered = register(schedule, center: center)
                }
                if registered {
                    signatures[schedule.id.uuidString] = signature
                    failedRuleIDs.remove(schedule.id)
                } else {
                    failedRuleIDs.insert(schedule.id)
                }
            }
        }

        for limit in limits {
            liveIDs.insert(limit.id)
            guard let profile = profilesByID[limit.profileID] else { continue }
            let rule = rule(id: limit.id, name: "\(profile.name) limit", profile: profile, schedule: nil)
            rules[limit.id] = rule
            // The apps are part of the usage event, so they're in the signature.
            let signature = Self.signature(limit, rule: rule)
            guard signatures[limit.id.uuidString] != signature, !isLocked(limit) else { continue }
            let name = DeviceActivityName(RuleActivity.limitName(limit.id))
            center.stopMonitoring([name])
            ManagedSettingsStore.forRule(limit.id).clearAllSettings()
            if limit.isEnabled, Self.hasApps(rule) {
                register(limit, rule: rule, name: name, center: center)
            }
            signatures[limit.id.uuidString] = signature
        }

        // Clean up anything deleted.
        for id in Set(rules.keys).subtracting(liveIDs) {
            rules[id] = nil
            signatures[id.uuidString] = nil
            center.stopMonitoring(Self.activityNames(for: id) + [DeviceActivityName(RuleActivity.limitName(id))])
            ManagedSettingsStore.forRule(id).clearAllSettings()
        }

        GooseShared.rules = rules
        UserDefaults.standard.set(try? JSONEncoder().encode(signatures), forKey: signaturesKey)
        enforceSchedules()
    }

    /// Starts and ends scheduled locks by the clock whenever the app runs.
    /// iOS doesn't always send "interval started" for a schedule saved partway
    /// through its window. ScheduledLock acts once per run, so this and the
    /// monitor never double up.
    func enforceSchedules(at date: Date = Date()) {
        let rules = GooseShared.rules
        for schedule in schedules {
            if schedule.isActive(at: date) {
                if let rule = rules[schedule.id], Self.hasApps(rule) {
                    ScheduledLock.begin(rule, at: date)
                }
            } else {
                ScheduledLock.end(scheduleID: schedule.id, at: date)
            }
        }
    }

    @discardableResult
    private func register(_ schedule: BlockSchedule, center: DeviceActivityCenter) -> Bool {
        func components(_ hour: Int, _ minute: Int, weekday: Int?) -> DateComponents {
            var c = DateComponents(hour: hour, minute: minute)
            c.weekday = weekday
            return c
        }
        do {
            if schedule.weekdays.count == 7 {
                try center.startMonitoring(
                    DeviceActivityName(RuleActivity.scheduleName(schedule.id)),
                    during: DeviceActivitySchedule(
                        intervalStart: components(schedule.startHour, schedule.startMinute, weekday: nil),
                        intervalEnd: components(schedule.endHour, schedule.endMinute, weekday: nil),
                        repeats: true
                    )
                )
            } else {
                for day in schedule.weekdays {
                    let endDay = schedule.crossesMidnight ? day % 7 + 1 : day
                    try center.startMonitoring(
                        DeviceActivityName(RuleActivity.scheduleName(schedule.id, weekday: day)),
                        during: DeviceActivitySchedule(
                            intervalStart: components(schedule.startHour, schedule.startMinute, weekday: day),
                            intervalEnd: components(schedule.endHour, schedule.endMinute, weekday: endDay),
                            repeats: true
                        )
                    )
                }
            }
        } catch {
            NSLog("Couldn't schedule \(schedule.name): \(error)")
            return false
        }
        return true
    }

    private func register(_ limit: DailyLimit, rule: BlockRule, name: DeviceActivityName, center: DeviceActivityCenter) {
        let event = DeviceActivityEvent(
            applications: rule.appTokens,
            categories: rule.categoryTokens,
            webDomains: rule.webDomainTokens,
            threshold: DateComponents(minute: limit.minutes)
        )
        do {
            try center.startMonitoring(
                name,
                during: DeviceActivitySchedule(
                    intervalStart: DateComponents(hour: 0, minute: 0),
                    intervalEnd: DateComponents(hour: 23, minute: 59, second: 59),
                    repeats: true
                ),
                events: [DeviceActivityEvent.Name(RuleActivity.limitEvent): event]
            )
        } catch {
            NSLog("Couldn't start the daily limit: \(error)")
        }
    }

    private static func activityNames(for id: UUID) -> [DeviceActivityName] {
        ([nil] + (1...7).map(Optional.some)).map { DeviceActivityName(RuleActivity.scheduleName(id, weekday: $0)) }
    }

    private static func hasApps(_ rule: BlockRule) -> Bool {
        !rule.appTokens.isEmpty || !rule.categoryTokens.isEmpty || !rule.webDomainTokens.isEmpty
    }

    private func rule(id: UUID, name: String, profile: Profile, schedule: BlockSchedule?) -> BlockRule {
        BlockRule(
            id: id,
            name: name,
            profileID: profile.id,
            profileName: profile.name,
            unlockMethod: profile.unlockMethod,
            appTokens: profile.appTokens,
            categoryTokens: profile.categoryTokens,
            webDomainTokens: profile.webDomainTokens,
            schedule: schedule
        )
    }

    // Sets iterate in a different order each launch, so everything is sorted
    // here. An unstable signature would restart every limit on every launch.
    static func signature(_ schedule: BlockSchedule) -> String {
        "\(schedule.isEnabled)|\(schedule.startHour):\(schedule.startMinute)-\(schedule.endHour):\(schedule.endMinute)|\(schedule.weekdays.sorted())"
    }

    static func signature(_ limit: DailyLimit, rule: BlockRule) -> String {
        func sorted<T: Encodable>(_ tokens: Set<T>) -> [String] {
            tokens.compactMap { (try? JSONEncoder().encode($0)).map { $0.base64EncodedString() } }.sorted()
        }
        let tokens = sorted(rule.appTokens) + sorted(rule.categoryTokens) + sorted(rule.webDomainTokens)
        return "\(limit.isEnabled)|\(limit.minutes)|" + tokens.joined(separator: ",")
    }

    // MARK: Storage

    private func persist() {
        UserDefaults.standard.set(try? JSONEncoder().encode(schedules), forKey: schedulesKey)
        UserDefaults.standard.set(try? JSONEncoder().encode(limits), forKey: limitsKey)
    }

    private func load<T: Decodable>(_ key: String) -> [T] {
        load(key, default: [])
    }

    private func load<T: Decodable>(_ key: String, default fallback: T) -> T {
        guard let data = UserDefaults.standard.data(forKey: key),
              let value = try? JSONDecoder().decode(T.self, from: data) else { return fallback }
        return value
    }
}
