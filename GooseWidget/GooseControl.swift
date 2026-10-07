// Also what shows up under Settings → Action Button → Controls.

import WidgetKit
import SwiftUI
import AppIntents

struct GooseControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "GooseControl", provider: Provider()) { isBlocking in
            ControlWidgetButton(action: GooseLockIntent()) {
                Label(isBlocking ? "Goosed" : "Lock Goose", systemImage: isBlocking ? "lock.fill" : "lock.open.fill")
            }
        }
        .displayName("Goose")
        .description("Opens Goose to lock or unlock.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }

        func currentValue() async throws -> Bool {
            GooseShared.appearsLocked
        }
    }
}
