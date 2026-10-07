import WidgetKit
import SwiftUI
import AppIntents

// Same slate gray as the app icon and the main screen.
private let slate = Color(red: 0.231, green: 0.227, blue: 0.247)

struct GooseEntry: TimelineEntry {
    let date: Date
    let isBlocking: Bool
    let blockStartDate: Date?
    /// Set for timer locks and reached daily limits, which end at midnight.
    let blockEndDate: Date?
    let profileName: String?

    static let placeholder = GooseEntry(date: .now, isBlocking: false, blockStartDate: nil, blockEndDate: nil, profileName: "Default")

    /// Locked by a reached daily limit rather than a lock.
    var isLimit = false

    var lockIcon: String {
        guard isBlocking else { return "lock.open.fill" }
        return blockEndDate == nil || isLimit ? "lock.fill" : "hourglass"
    }

    /// Counts down for timer locks, up for everything else.
    @ViewBuilder
    var clock: some View {
        if let end = blockEndDate {
            Text(timerInterval: date...max(date, end), countsDown: true)
        } else if let start = blockStartDate {
            Text(start, style: .timer)
        }
    }
}

struct GooseProvider: TimelineProvider {
    func placeholder(in context: Context) -> GooseEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (GooseEntry) -> Void) {
        completion(context.isPreview ? .placeholder : currentEntry())
    }

    // The app reloads timelines whenever it locks or unlocks, and the clock
    // text ticks on its own. A timer lock adds a second entry for when it
    // ends, so the widget flips back even if Goose never opens.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GooseEntry>) -> Void) {
        let entry = currentEntry()
        var entries = [entry]
        if entry.isBlocking, let end = entry.blockEndDate, end > entry.date {
            entries.append(GooseEntry(date: end, isBlocking: false, blockStartDate: nil, blockEndDate: nil, profileName: entry.profileName))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func currentEntry() -> GooseEntry {
        let end = GooseShared.blockEndDate
        let isBlocking = GooseShared.isBlocking && (end.map { $0 > .now } ?? true)
        if !isBlocking, let limitName = GooseShared.reachedLimitName {
            // A reached limit lasts until midnight.
            let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: .now))!
            return GooseEntry(date: .now, isBlocking: true, blockStartDate: nil, blockEndDate: midnight, profileName: limitName, isLimit: true)
        }
        return GooseEntry(
            date: .now,
            isBlocking: isBlocking,
            blockStartDate: isBlocking ? GooseShared.blockStartDate : nil,
            blockEndDate: isBlocking ? end : nil,
            profileName: GooseShared.activeProfileName
        )
    }
}

struct GooseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GooseEntry

    private var accent: Color { SkyPeriod.current(for: entry.date).color }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Image("GooseMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 58, height: 58)
                Spacer()
                actionButton
            }

            Spacer(minLength: 4)

            Text(entry.isBlocking ? "Goosed" : "On the loose")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(.white)

            if entry.isBlocking {
                entry.clock
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text(entry.profileName ?? "Default")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .containerBackground(slate, for: .widget)
    }

    private var actionButton: some View {
        Button(intent: GooseLockIntent()) {
            circleIcon(entry.lockIcon, fill: entry.isBlocking ? Color(white: 0.18) : accent)
        }
        .buttonStyle(.plain)
    }

    private func circleIcon(_ symbol: String, fill: Color) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 42, height: 42)
            .background(Circle().fill(fill))
    }

    // MARK: Lock Screen

    private var circular: some View {
        Button(intent: GooseLockIntent()) {
            Image(systemName: entry.lockIcon)
                .font(.system(size: 22, weight: .semibold))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var rectangular: some View {
        Button(intent: GooseLockIntent()) {
            HStack(spacing: 8) {
                Image(systemName: entry.lockIcon)
                    .font(.system(size: 20, weight: .semibold))
                VStack(alignment: .leading, spacing: 0) {
                    Text(entry.isBlocking ? "Goosed" : "On the loose")
                        .font(.headline)
                    if entry.isBlocking {
                        entry.clock.monospacedDigit()
                    } else {
                        Text("Tap to lock")
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .containerBackground(for: .widget) { Color.clear }
    }
}

struct GooseWidget: Widget {
    let kind = "GooseWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: GooseProvider()) { entry in
            GooseWidgetView(entry: entry)
        }
        .configurationDisplayName("Goose")
        .description("Shows whether you're blocked, and opens Goose to lock or unlock.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}
