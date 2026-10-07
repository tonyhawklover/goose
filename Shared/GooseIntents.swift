import AppIntents

/// What the widget, Control Center control and Action Button run: open Goose
/// and do whatever the profile's unlock method calls for (scan, start the
/// timer, or toggle). Nothing locks or unlocks without the app in front.
struct GooseLockIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock or Unlock Goose"
    static let description = IntentDescription("Opens Goose to lock or unlock with your profile's unlock method.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @MainActor
    func perform() async throws -> some IntentResult {
        GooseShared.requestLockAction()
        return .result()
    }
}
