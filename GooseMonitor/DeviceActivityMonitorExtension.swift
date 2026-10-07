import DeviceActivity
import ManagedSettings
import Foundation

/// iOS wakes this as timer locks, schedules and daily limits start, end or
/// hit their threshold, even when Goose isn't running.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let name = activity.rawValue
        guard let id = RuleActivity.ruleID(in: name) else { return }

        if name.hasPrefix(RuleActivity.schedulePrefix) {
            guard let rule = GooseShared.rules[id] else { return }
            ScheduledLock.begin(rule, at: Date())
        } else {
            // A new day: the limit starts counting again.
            ManagedSettingsStore.forRule(id).clearAllSettings()
            GooseShared.setLimitReachedDate(nil, for: id)
            GooseShared.setLimitLiftedDate(nil, for: id)
            GooseShared.setReachedLimitName(nil)
            GooseShared.reloadSurfaces()
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let name = activity.rawValue

        if name == GooseShared.timerActivityName {
            endTimerLock()
            return
        }

        guard let id = RuleActivity.ruleID(in: name) else { return }
        if name.hasPrefix(RuleActivity.schedulePrefix) {
            ScheduledLock.end(scheduleID: id, at: Date())
        } else {
            ManagedSettingsStore.forRule(id).clearAllSettings()
            GooseShared.setLimitReachedDate(nil, for: id)
            GooseShared.setLimitLiftedDate(nil, for: id)
            GooseShared.setReachedLimitName(nil)
            GooseShared.reloadSurfaces()
        }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let id = RuleActivity.ruleID(in: activity.rawValue), let rule = GooseShared.rules[id] else { return }
        ManagedSettingsStore.forRule(id).apply(rule)
        GooseShared.setLimitReachedDate(Date(), for: id)
        GooseShared.setReachedLimitName(rule.profileName)
        GooseShared.reloadSurfaces()
    }

    /// Only ends a lock with an end time that's actually due. If the app
    /// already ended it and something else is locked now, that's left alone.
    private func endTimerLock() {
        guard GooseShared.isBlocking,
              let end = GooseShared.blockEndDate,
              end <= Date().addingTimeInterval(60) else { return }

        ManagedSettingsStore().clearAllSettings()
        GooseShared.isBlocking = false
        GooseShared.reloadSurfaces()
    }
}
