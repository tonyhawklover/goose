import WidgetKit
import SwiftUI

@main
struct GooseWidgetBundle: WidgetBundle {
    var body: some Widget {
        GooseWidget()
        GooseControl()
    }
}
