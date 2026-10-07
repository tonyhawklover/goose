// Compiled into the app and the monitor extension. Schedules and daily limits
// run in the monitor while Goose isn't open, so everything they need lives
// in the App Group.

import Foundation
import ManagedSettings

struct BlockSession: Identifiable, Codable {
    let id: UUID
    let start: Date
    let end: Date
    let profileName: String

    var duration: TimeInterval { end.timeIntervalSince(start) }

    init(start: Date, end: Date, profileName: String) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.profileName = profileName
    }
}

/// Locks a profile automatically between two times on chosen days.
struct BlockSchedule: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var profileID: UUID
    var startHour = 21
    var startMinute = 0
    var endHour = 7
    var endMinute = 0
    /// Calendar weekdays, 1 = Sunday.
    var weekdays: Set<Int> = Set(1...7)
    var isEnabled = true

    /// DeviceActivity won't run anything shorter than this.
    static let minimumMinutes = 15

    private var startMinutes: Int { startHour * 60 + startMinute }
    private var endMinutes: Int { endHour * 60 + endMinute }

    var crossesMidnight: Bool { endMinutes <= startMinutes }
    var durationMinutes: Int { (endMinutes - startMinutes + 24 * 60) % (24 * 60) }

    /// Whether the window is open at `date`. An overnight window belongs to
    /// the day it started, so Monday 9pm to 7am is open early Tuesday.
    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        activeStart(at: date, calendar: calendar) != nil
    }

    /// When the window that's open at `date` started. Also identifies that
    /// run of the schedule, so it only locks once per run.
    func activeStart(at date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        let weekday = calendar.component(.weekday, from: date)
        let now = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        let todayStart = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: date)!

        if crossesMidnight {
            if now >= startMinutes && weekdays.contains(weekday) { return todayStart }
            let yesterday = weekday == 1 ? 7 : weekday - 1
            if now < endMinutes && weekdays.contains(yesterday) {
                return calendar.date(byAdding: .day, value: -1, to: todayStart)
            }
            return nil
        }
        return weekdays.contains(weekday) && now >= startMinutes && now < endMinutes ? todayStart : nil
    }

    /// The next time the schedule starts after `date`.
    func nextStart(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date),
                  let start = calendar.date(bySettingHour: startHour, minute: startMinute, second: 0, of: day) else { continue }
            if start > date && weekdays.contains(calendar.component(.weekday, from: start)) {
                return start
            }
        }
        return nil
    }

    /// When the window that's open at `date` closes.
    func activeEnd(at date: Date, calendar: Calendar = .current) -> Date? {
        activeStart(at: date, calendar: calendar)?.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

/// What the monitor needs to act on a schedule or daily limit without the
/// app: the profile's apps and how it unlocks.
struct BlockRule: Codable, Equatable {
    let id: UUID
    var name: String
    var profileID: UUID
    var profileName: String
    var unlockMethod: UnlockMethod
    var appTokens: Set<ApplicationToken>
    var categoryTokens: Set<ActivityCategoryToken>
    var webDomainTokens: Set<WebDomainToken>
    /// Set for schedules, nil for daily limits.
    var schedule: BlockSchedule?
}

/// DeviceActivity names: "schedule-<id>" (every day) or "schedule-<id>-<weekday>",
/// and "limit-<id>".
enum RuleActivity {
    static let schedulePrefix = "schedule-"
    static let limitPrefix = "limit-"
    static let limitEvent = "limit"

    static func scheduleName(_ id: UUID, weekday: Int? = nil) -> String {
        schedulePrefix + id.uuidString + (weekday.map { "-\($0)" } ?? "")
    }

    static func limitName(_ id: UUID) -> String {
        limitPrefix + id.uuidString
    }

    static func ruleID(in name: String) -> UUID? {
        for prefix in [schedulePrefix, limitPrefix] where name.hasPrefix(prefix) {
            return UUID(uuidString: String(name.dropFirst(prefix.count).prefix(36)))
        }
        return nil
    }
}

extension ManagedSettingsStore {
    /// Each daily limit shields through its own store. iOS combines every
    /// store's shields, so a limit never lifts the main lock or vice versa.
    static func forRule(_ id: UUID) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name("rule-" + id.uuidString))
    }

    func apply(_ rule: BlockRule) {
        shield.applications = rule.appTokens.isEmpty ? nil : rule.appTokens
        shield.applicationCategories = rule.categoryTokens.isEmpty ? .none : .specific(rule.categoryTokens)
        shield.webDomains = rule.webDomainTokens.isEmpty ? nil : rule.webDomainTokens
    }
}

/// A schedule locks the same way the lock button does, so it unlocks the
/// same way too: with the profile's tag, a tap, or (for timers) at the end.
enum ScheduledLock {
    static func begin(_ rule: BlockRule, at date: Date) {
        guard let schedule = rule.schedule, let start = schedule.activeStart(at: date) else { return }
        // Once per run: unlocking early shouldn't be undone a minute later.
        guard GooseShared.lastScheduleRun(rule.id) != start else { return }
        GooseShared.setLastScheduleRun(start, for: rule.id)
        guard !GooseShared.isBlocking else { return }

        ManagedSettingsStore().apply(rule)
        GooseShared.isBlocking = true
        GooseShared.blockStartDate = date
        GooseShared.blockEndDate = rule.unlockMethod == .timer ? schedule.activeEnd(at: date) : nil
        GooseShared.activeUnlockMethod = rule.unlockMethod
        GooseShared.lockedProfileID = rule.profileID
        GooseShared.lockedProfileName = rule.profileName
        GooseShared.lockingScheduleID = rule.id
        GooseShared.reloadSurfaces()
    }

    /// Unlocks only if this schedule's lock is still the one in place.
    static func end(scheduleID: UUID, at date: Date) {
        guard GooseShared.isBlocking, GooseShared.lockingScheduleID == scheduleID else { return }
        ManagedSettingsStore().clearAllSettings()
        GooseShared.isBlocking = false
        // Left for the app, which records the block in history when it next opens.
        GooseShared.blockEndDate = date
        GooseShared.lockingScheduleID = nil
        GooseShared.reloadSurfaces()
    }
}

extension GooseShared {
    private enum RuleKey {
        static let rules = "blockRules"
        static let lockedProfileID = "lockedProfileID"
        static let lockedProfileName = "lockedProfileName"
        static let lockingScheduleID = "lockingScheduleID"
        static func limitReached(_ id: UUID) -> String { "limitReached-" + id.uuidString }
        static func limitLifted(_ id: UUID) -> String { "limitLifted-" + id.uuidString }
        static func lastScheduleRun(_ id: UUID) -> String { "lastScheduleRun-" + id.uuidString }
    }

    static var rules: [UUID: BlockRule] {
        get {
            guard let data = defaults.data(forKey: RuleKey.rules),
                  let rules = try? JSONDecoder().decode([UUID: BlockRule].self, from: data) else { return [:] }
            return rules
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: RuleKey.rules) }
    }

    /// The profile the current lock belongs to. A schedule can lock a profile
    /// other than the one selected, and unlocking checks this one's tags.
    static var lockedProfileID: UUID? {
        get { defaults.string(forKey: RuleKey.lockedProfileID).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: RuleKey.lockedProfileID) }
    }

    static var lockedProfileName: String? {
        get { defaults.string(forKey: RuleKey.lockedProfileName) }
        set { defaults.set(newValue, forKey: RuleKey.lockedProfileName) }
    }

    /// Set when a schedule made the current lock, so its end only undoes its own.
    static var lockingScheduleID: UUID? {
        get { defaults.string(forKey: RuleKey.lockingScheduleID).flatMap(UUID.init) }
        set { defaults.set(newValue?.uuidString, forKey: RuleKey.lockingScheduleID) }
    }

    static func lastScheduleRun(_ id: UUID) -> Date? {
        defaults.object(forKey: RuleKey.lastScheduleRun(id)) as? Date
    }

    static func setLastScheduleRun(_ date: Date?, for id: UUID) {
        defaults.set(date, forKey: RuleKey.lastScheduleRun(id))
    }

    /// The day a limit was reached, so the app can show it and lock its settings.
    static func limitReachedDate(_ id: UUID) -> Date? {
        defaults.object(forKey: RuleKey.limitReached(id)) as? Date
    }

    static func setLimitReachedDate(_ date: Date?, for id: UUID) {
        defaults.set(date, forKey: RuleKey.limitReached(id))
    }

    /// When a reached limit was unlocked with the profile's tag for the rest of the day.
    static func limitLiftedDate(_ id: UUID) -> Date? {
        defaults.object(forKey: RuleKey.limitLifted(id)) as? Date
    }

    static func setLimitLiftedDate(_ date: Date?, for id: UUID) {
        defaults.set(date, forKey: RuleKey.limitLifted(id))
    }
}
