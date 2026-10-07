// Compiled into the app, the widget and the monitor extension. Each runs in
// its own process, so the blocking state lives in the App Group.

import Foundation
import SwiftUI
import WidgetKit

enum UnlockMethod: String, Codable, CaseIterable, Identifiable {
    case key, timer, button

    var id: String { rawValue }

    var label: String {
        switch self {
        case .key: return "Tag or QR"
        case .timer: return "Timer"
        case .button: return "Button"
        }
    }

    var icon: String {
        switch self {
        case .key: return "key.fill"
        case .timer: return "hourglass"
        case .button: return "hand.tap.fill"
        }
    }
}

enum GooseShared {
    /// Set per-build from Config/Goose.xcconfig via each target's Info.plist.
    static let appGroupID = Bundle.main.object(forInfoDictionaryKey: "GooseAppGroup") as! String
    static let defaults = UserDefaults(suiteName: appGroupID)!

    /// Posted in the app process when the widget or Action Button intent runs.
    static let lockActionRequested = Notification.Name("GooseLockActionRequested")

    /// The DeviceActivity name the timer lock is scheduled under.
    static let timerActivityName = "gooseTimer"

    // The shield extension reads blockEndDate and activeAccentColor by these
    // raw names, since it doesn't compile this file.
    private enum Key {
        static let isBlocking = "isBlocking"
        static let blockStartDate = "blockStartDate"
        static let blockEndDate = "blockEndDate"
        static let activeUnlockMethod = "activeUnlockMethod"
        static let activeProfileName = "activeProfileName"
        static let accentColor = "activeAccentColor"
        static let pendingLockAction = "pendingLockAction"
        static let reachedLimitName = "reachedLimitName"
        static let reachedLimitDate = "reachedLimitDate"
    }

    // MARK: State

    static var isBlocking: Bool {
        get { defaults.bool(forKey: Key.isBlocking) }
        set { defaults.set(newValue, forKey: Key.isBlocking) }
    }

    static var blockStartDate: Date? {
        get { date(forKey: Key.blockStartDate) }
        set { setDate(newValue, forKey: Key.blockStartDate) }
    }

    /// Only set for timer locks.
    static var blockEndDate: Date? {
        get { date(forKey: Key.blockEndDate) }
        set { setDate(newValue, forKey: Key.blockEndDate) }
    }

    static var activeUnlockMethod: UnlockMethod {
        get { defaults.string(forKey: Key.activeUnlockMethod).flatMap(UnlockMethod.init) ?? .key }
        set { defaults.set(newValue.rawValue, forKey: Key.activeUnlockMethod) }
    }

    static var activeProfileName: String? {
        get { defaults.string(forKey: Key.activeProfileName) }
        set { defaults.set(newValue, forKey: Key.activeProfileName) }
    }

    static var accentColorName: String? {
        get { defaults.string(forKey: Key.accentColor) }
        set { defaults.set(newValue, forKey: Key.accentColor) }
    }

    /// A daily limit that's been reached and not unlocked, for the widget and
    /// control, which can't read the limit rules. Only counts on the day it
    /// was set, so it lapses at midnight even if nothing clears it.
    static var reachedLimitName: String? {
        guard let set = date(forKey: Key.reachedLimitDate), Calendar.current.isDateInToday(set) else { return nil }
        return defaults.string(forKey: Key.reachedLimitName)
    }

    static func setReachedLimitName(_ name: String?) {
        defaults.set(name, forKey: Key.reachedLimitName)
        setDate(name == nil ? nil : Date(), forKey: Key.reachedLimitDate)
    }

    /// What the widget and control show as locked: a lock or a reached limit.
    static var appearsLocked: Bool { isBlocking || reachedLimitName != nil }

    private static func date(forKey key: String) -> Date? {
        (defaults.object(forKey: key) as? TimeInterval).map(Date.init(timeIntervalSince1970:))
    }

    private static func setDate(_ date: Date?, forKey key: String) {
        if let date {
            defaults.set(date.timeIntervalSince1970, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: Lock action hand-off

    static func requestLockAction() {
        defaults.set(true, forKey: Key.pendingLockAction)
        NotificationCenter.default.post(name: lockActionRequested, object: nil)
    }

    static func consumePendingLockAction() -> Bool {
        guard defaults.bool(forKey: Key.pendingLockAction) else { return false }
        defaults.set(false, forKey: Key.pendingLockAction)
        return true
    }

    // MARK: Refresh

    static func reloadSurfaces() {
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            ControlCenter.shared.reloadAllControls()
        }
    }
}

// MARK: - Sky period

/// Bucketed by local hour instead of real sun position, which would need
/// location access.
enum SkyPeriod: String, Equatable {
    case sunrise, day, sunset, twilight, night

    static func current(for date: Date) -> SkyPeriod {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<8: return .sunrise
        case 8..<17: return .day
        case 17..<19: return .sunset
        case 19..<21: return .twilight
        default: return .night
        }
    }

    var color: Color {
        switch self {
        case .sunrise: return Color(red: 1.00, green: 0.62, blue: 0.35)
        case .day: return Color(red: 1.00, green: 0.78, blue: 0.24)
        case .sunset: return Color(red: 1.00, green: 0.45, blue: 0.30)
        case .twilight: return Color(red: 0.62, green: 0.45, blue: 0.82)
        case .night: return Color(red: 0.56, green: 0.66, blue: 0.82)
        }
    }
}
