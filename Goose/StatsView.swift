import SwiftUI
import Charts

/// Numbers for the stats screen, from finished blocks.
struct BlockStats {
    let sessions: [BlockSession]
    let now: Date
    var calendar = Calendar.current

    /// Time blocked within one calendar day. A block that runs past midnight
    /// counts toward both days.
    func blocked(on day: Date) -> TimeInterval {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        return sessions.reduce(0) { total, session in
            let overlap = min(session.end, end).timeIntervalSince(max(session.start, start))
            return total + max(0, overlap)
        }
    }

    /// Oldest first, ending today.
    var lastSevenDays: [(day: Date, seconds: TimeInterval)] {
        (0..<7).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: calendar.startOfDay(for: now)).map { ($0, blocked(on: $0)) }
        }
    }

    var today: TimeInterval { blocked(on: now) }

    var lastSevenDaysTotal: TimeInterval { lastSevenDays.reduce(0) { $0 + $1.seconds } }

    /// Days in a row with any blocked time. Today without a block yet doesn't
    /// break the streak; it just isn't counted.
    var streak: Int {
        var day = calendar.startOfDay(for: now)
        if blocked(on: day) == 0 {
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        var count = 0
        while blocked(on: day) > 0 {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    var longest: TimeInterval { sessions.map(\.duration).max() ?? 0 }
}

struct StatsView: View {
    @EnvironmentObject private var appBlocker: AppBlocker

    private var stats: BlockStats { BlockStats(sessions: appBlocker.history, now: Date()) }

    var body: some View {
        List {
            Section {
                Chart(stats.lastSevenDays, id: \.day) { entry in
                    BarMark(
                        x: .value("Day", entry.day, unit: .day),
                        y: .value("Hours", entry.seconds / 3600)
                    )
                    .foregroundStyle(SkyPeriod.current(for: Date()).color)
                    .cornerRadius(4)
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day)) { _ in
                        AxisValueLabel(format: .dateTime.weekday(.narrow))
                    }
                }
                .chartYAxisLabel("Hours")
                .overlay {
                    if stats.lastSevenDaysTotal == 0 {
                        Text("Finished blocks show up here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(height: 180)
                .padding(.vertical, 8)
            } header: {
                Text("Last 7 Days")
            } footer: {
                Text("\(formatDuration(stats.lastSevenDaysTotal)) blocked")
            }

            Section {
                statRow("Today", formatDuration(stats.today), icon: "sun.max")
                statRow("Streak", stats.streak == 1 ? "1 day" : "\(stats.streak) days", icon: "flame")
                statRow("Longest block", formatDuration(stats.longest), icon: "trophy")
                statRow("Blocks finished", "\(appBlocker.history.count)", icon: "checkmark.circle")
            } footer: {
                Text("Counts finished blocks, including schedules. Daily limits aren't counted.")
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func statRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let minutes = Int(interval) / 60
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m"
}
