import ManagedSettings
import ManagedSettingsUI
import UIKit

// Runs in its own process, so anything from the app (the accent color and the
// goose icon) comes through the App Group.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(subjectName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(subjectName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(subjectName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(subjectName: webDomain.domain)
    }

    /// Set per-build from Config/Goose.xcconfig via Info.plist.
    private let appGroupID = Bundle.main.object(forInfoDictionaryKey: "GooseAppGroup") as! String

    private func makeConfiguration(subjectName: String?) -> ShieldConfiguration {
        let shared = UserDefaults(suiteName: appGroupID)
        let accent = SharedTint.color(named: shared?.string(forKey: "activeAccentColor"))

        return ShieldConfiguration(
            backgroundBlurStyle: .systemMaterialDark,
            backgroundColor: UIColor(red: 0.06, green: 0.07, blue: 0.08, alpha: 1.0),
            icon: sharedGooseIcon() ?? UIImage(systemName: "lock.fill")?
                .withTintColor(.white, renderingMode: .alwaysOriginal)
                .withConfiguration(UIImage.SymbolConfiguration(pointSize: 46, weight: .semibold)),
            title: ShieldConfiguration.Label(
                text: "\(subjectName ?? "This") is Goosed",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: subtitle(shared),
                color: UIColor.white.withAlphaComponent(0.75)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Okay", color: .white),
            primaryButtonBackgroundColor: accent
        )
    }

    /// During a timer lock, says when it ends. "blockEndDate" is written by
    /// GooseShared in the app.
    private func subtitle(_ shared: UserDefaults?) -> String {
        if let interval = shared?.object(forKey: "blockEndDate") as? TimeInterval {
            let end = Date(timeIntervalSince1970: interval)
            if end > Date() {
                return "Unlocks at \(end.formatted(date: .omitted, time: .shortened))."
            }
        }
        return ShieldTaglines.random()
    }

    /// Nil until the app writes it on the first lock; callers fall back to a lock symbol.
    private func sharedGooseIcon() -> UIImage? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let iconURL = containerURL.appendingPathComponent("shield-icon.png")
        guard let data = try? Data(contentsOf: iconURL) else { return nil }
        return UIImage(data: data)
    }
}

/// Separate from the app's reflections: the shield's subtitle has little room,
/// and this target can't see `Reflection` anyway.
enum ShieldTaglines {
    static func random() -> String {
        all.randomElement()!
    }

    static let all: [String] = [
        "This can wait.",
        "Not now. You know why.",
        "Go do the thing you actually wanted to do.",
        "Still blocked, on purpose.",
        "You already decided this one.",
        "The scroll will still be boring later.",
        "Worth the walk back to your tag.",
        "This is the friction working.",
        "Nothing in here is going anywhere.",
        "You picked this. Trust past you.",
    ]
}

/// Mirrors `SkyPeriod.color`, which this target can't import. Keep them in sync.
enum SharedTint {
    static func color(named name: String?) -> UIColor {
        switch name {
        case "sunrise": return UIColor(red: 1.00, green: 0.62, blue: 0.35, alpha: 1)
        case "day": return UIColor(red: 1.00, green: 0.78, blue: 0.24, alpha: 1)
        case "sunset": return UIColor(red: 1.00, green: 0.45, blue: 0.30, alpha: 1)
        case "twilight": return UIColor(red: 0.62, green: 0.45, blue: 0.82, alpha: 1)
        case "night": return UIColor(red: 0.56, green: 0.66, blue: 0.82, alpha: 1)
        default: return UIColor(red: 0.30, green: 0.30, blue: 0.32, alpha: 1)
        }
    }
}
