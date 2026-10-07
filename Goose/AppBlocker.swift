//
//  AppBlocker.swift
//  Goose
//
//  Created by Oz Tamir on 22/08/2024.
//  Modified for Goose.
//
import SwiftUI
import UIKit
import ManagedSettings
import FamilyControls
import DeviceActivity

/// DeviceActivity refuses to monitor intervals shorter than 15 minutes, so a
/// short timer's monitoring window starts in the past. The extra minute covers
/// rounding to whole seconds.
enum TimerWindow {
    static let minimumLength: TimeInterval = 16 * 60

    static func monitoringStart(endingAt end: Date, now: Date) -> Date {
        min(now, end.addingTimeInterval(-minimumLength))
    }
}

class AppBlocker: ObservableObject {
    let store = ManagedSettingsStore()
    @Published var isBlocking = false
    @Published var isAuthorized = false
    @Published var blockStartDate: Date?
    @Published var blockEndDate: Date?
    @Published var activeMethod: UnlockMethod = .key
    /// The profile the current lock belongs to; a schedule can lock one that
    /// isn't selected.
    @Published var lockedProfileID: UUID?
    /// Set when a schedule made the current lock.
    @Published var lockingScheduleID: UUID?
    @Published var history: [BlockSession] = []

    private let historyLimit = 200

    init() {
        loadHistory()
        refresh()
        Task {
            await requestAuthorization()
        }
    }
    
    func requestAuthorization() async {
        #if targetEnvironment(simulator)
        // Shields never apply in the Simulator and its auth prompt is flaky,
        // so skip it rather than get stuck behind a dialog while iterating on UI.
        DispatchQueue.main.async {
            self.isAuthorized = true
        }
        #else
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            DispatchQueue.main.async {
                self.isAuthorized = true
            }
        } catch {
            print("Failed to request authorization: \(error)")
            DispatchQueue.main.async {
                self.isAuthorized = false
            }
        }
        #endif
    }

    func lock(_ profile: Profile, accentColorName: String) {
        guard isAuthorized, !isBlocking else { return }
        let now = Date()

        if profile.unlockMethod == .timer {
            let end = now.addingTimeInterval(TimeInterval(profile.timerMinutes * 60))
            Self.scheduleLockEnd(at: end, now: now)
            blockEndDate = end
        } else {
            blockEndDate = nil
        }

        store.shield.applications = profile.appTokens.isEmpty ? nil : profile.appTokens
        store.shield.applicationCategories = profile.categoryTokens.isEmpty ? .none : .specific(profile.categoryTokens)
        store.shield.webDomains = profile.webDomainTokens.isEmpty ? nil : profile.webDomainTokens
        // The GooseShield extension reads this to color its button.
        GooseShared.accentColorName = accentColorName
        writeSharedIconIfNeeded()

        isBlocking = true
        blockStartDate = now
        activeMethod = profile.unlockMethod
        lockedProfileID = profile.id
        lockingScheduleID = nil
        GooseShared.lockedProfileName = profile.name
        saveBlockingState()
    }

    /// Timer locks can't be ended early; `refresh()` ends them when time is up.
    func unlock() {
        guard isBlocking, activeMethod != .timer else { return }
        finishBlock(at: Date())
    }

    /// Picks up locks a schedule started, ends a timer lock whose time is up,
    /// and records a lock the monitor ended while the app wasn't running.
    func refresh() {
        isBlocking = GooseShared.isBlocking
        blockStartDate = GooseShared.blockStartDate
        blockEndDate = GooseShared.blockEndDate
        activeMethod = GooseShared.activeUnlockMethod
        lockedProfileID = GooseShared.lockedProfileID
        lockingScheduleID = GooseShared.lockingScheduleID

        if isBlocking, let end = blockEndDate, end <= Date() {
            finishBlock(at: end)
        } else if !isBlocking, blockStartDate != nil {
            finishBlock(at: blockEndDate ?? Date())
        }
    }

    private func finishBlock(at end: Date) {
        store.clearAllSettings()
        DeviceActivityCenter().stopMonitoring([DeviceActivityName(GooseShared.timerActivityName)])

        if let start = blockStartDate {
            let name = GooseShared.lockedProfileName ?? GooseShared.activeProfileName ?? "Default"
            record([BlockSession(start: start, end: end, profileName: name)])
        }

        isBlocking = false
        blockStartDate = nil
        blockEndDate = nil
        lockingScheduleID = nil
        saveBlockingState()
    }

    /// Has the monitor extension lift the lock at `end` if Goose isn't running.
    /// Used by timer locks and by schedule locks whose schedule was changed.
    static func scheduleLockEnd(at end: Date, now: Date = Date()) {
        #if !targetEnvironment(simulator)
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: TimerWindow.monitoringStart(endingAt: end, now: now)),
            intervalEnd: calendar.dateComponents(components, from: end),
            repeats: false
        )
        do {
            try DeviceActivityCenter().startMonitoring(DeviceActivityName(GooseShared.timerActivityName), during: schedule)
        } catch {
            // Still lock: the app ends the timer itself the next time it's opened.
            NSLog("Couldn't schedule the timer's end: \(error)")
        }
        #endif
    }

    /// The artwork only lives in the app's asset catalog, which the shield
    /// extension can't load, so it gets a PNG copy in the App Group container.
    private func writeSharedIconIfNeeded() {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: GooseShared.appGroupID) else { return }
        let iconURL = containerURL.appendingPathComponent("shield-icon.png")
        guard !FileManager.default.fileExists(atPath: iconURL.path) else { return }
        guard let image = UIImage(named: "GooseMark"), let data = image.pngData() else { return }
        try? data.write(to: iconURL)
    }

    // Stored in the App Group so the widget, shield and monitor can see it.
    private func saveBlockingState() {
        GooseShared.isBlocking = isBlocking
        GooseShared.blockStartDate = blockStartDate
        GooseShared.blockEndDate = blockEndDate
        GooseShared.activeUnlockMethod = activeMethod
        GooseShared.lockedProfileID = lockedProfileID
        GooseShared.lockingScheduleID = lockingScheduleID
        GooseShared.reloadSurfaces()
    }

    private func record(_ sessions: [BlockSession]) {
        history = (history + sessions).sorted { $0.end > $1.end }
        if history.count > historyLimit {
            history.removeLast(history.count - historyLimit)
        }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "blockHistory"),
              let decoded = try? JSONDecoder().decode([BlockSession].self, from: data) else { return }
        history = decoded
    }

    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(encoded, forKey: "blockHistory")
    }
}
