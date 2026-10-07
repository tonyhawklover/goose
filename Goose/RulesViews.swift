import SwiftUI

// MARK: - Schedules

struct SchedulesView: View {
    @EnvironmentObject private var rules: BlockRulesManager
    @EnvironmentObject private var appBlocker: AppBlocker
    @EnvironmentObject private var profileManager: ProfileManager
    @State private var editing: BlockSchedule?

    var body: some View {
        List {
            Section {
                ForEach(rules.schedules) { schedule in
                    Button {
                        editing = schedule
                    } label: {
                        ScheduleRow(
                            schedule: schedule,
                            profileName: profileName(schedule.profileID),
                            failed: rules.failedRuleIDs.contains(schedule.id),
                            isLockingNow: appBlocker.isBlocking && appBlocker.lockingScheduleID == schedule.id
                        )
                    }
                    .tint(.primary)
                }
                .onDelete { offsets in
                    for schedule in offsets.map({ rules.schedules[$0] }) {
                        rules.delete(schedule, profiles: profileManager.profiles)
                    }
                }
                Button {
                    editing = BlockSchedule(name: "", profileID: profileManager.currentProfile.id)
                } label: {
                    Label("Add a Schedule", systemImage: "plus")
                }
            } footer: {
                Text("Goose locks a profile automatically when a schedule starts, like every night at 9 PM, and unlocks it when the schedule ends. You can still unlock early the usual way for that profile.")
            }
        }
        .navigationTitle("Schedules")
        .navigationBarTitleDisplayMode(.inline)

        .sheet(item: $editing) { schedule in
            ScheduleEditor(schedule: schedule, isNew: !rules.schedules.contains { $0.id == schedule.id })
        }
    }

    private func profileName(_ id: UUID) -> String {
        profileManager.profiles.first { $0.id == id }?.name ?? "Deleted profile"
    }
}

private struct ScheduleRow: View {
    let schedule: BlockSchedule
    let profileName: String
    let failed: Bool
    let isLockingNow: Bool

    /// Whether this run already locked once (and was unlocked early, if it
    /// isn't locking now).
    private var ranThisWindow: Bool {
        guard let start = schedule.activeStart(at: Date()) else { return false }
        return GooseShared.lastScheduleRun(schedule.id) == start
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.name.isEmpty ? profileName : schedule.name)
                    .font(.body.weight(.medium))
                Text("\(timeRange(schedule)) · \(daysSummary(schedule.weekdays))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if failed {
                    Label("iOS couldn't schedule this. Try fewer schedules or choosing every day.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                if let end = schedule.activeEnd(at: Date()) {
                    Group {
                        if isLockingNow {
                            Label("Locked until \(end.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
                        } else if ranThisWindow, let next = schedule.nextStart(after: end) {
                            Label("Unlocked early. Starts again \(next.formatted(.dateTime.weekday(.abbreviated).hour().minute()))", systemImage: "lock.open.fill")
                        } else {
                            Label("On now, until \(end.formatted(date: .omitted, time: .shortened))", systemImage: "clock.fill")
                        }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
                }
            }
            Spacer()
            if !schedule.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(schedule.isEnabled ? 1 : 0.6)
        .padding(.vertical, 2)
    }
}

private struct ScheduleEditor: View {
    let isNew: Bool
    @EnvironmentObject private var rules: BlockRulesManager
    @EnvironmentObject private var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var schedule: BlockSchedule
    @State private var showSaveConfirmation = false
    @State private var confirmedSave = false

    init(schedule: BlockSchedule, isNew: Bool) {
        self.isNew = isNew
        _schedule = State(initialValue: schedule)
    }

    private var canSave: Bool {
        !schedule.weekdays.isEmpty && schedule.durationMinutes >= BlockSchedule.minimumMinutes
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (like Night or Work)", text: $schedule.name)
                    ProfileChooser(selection: $schedule.profileID)
                } footer: {
                    if needsKey {
                        Label(Self.keyWarning, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text(unlockExplanation)
                    }
                }

                Section {
                    DatePicker("Starts", selection: timeBinding(hour: \.startHour, minute: \.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(hour: \.endHour, minute: \.endMinute), displayedComponents: .hourAndMinute)
                } footer: {
                    if schedule.durationMinutes < BlockSchedule.minimumMinutes {
                        Text("Schedules need to be at least \(BlockSchedule.minimumMinutes) minutes long. iOS won't run shorter ones.")
                    } else if schedule.crossesMidnight {
                        Text("Ends the next morning.")
                    }
                }

                Section("Days") {
                    WeekdayPicker(selection: $schedule.weekdays)
                }

                Section {
                    Toggle("On", isOn: $schedule.isEnabled)
                }

                if !isNew {
                    Section {
                        Button("Delete Schedule", role: .destructive) {
                            rules.delete(schedule, profiles: profileManager.profiles)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            // Saved once the confirmation has closed, so the editor isn't
            // dismissed out from under it.
            .sheet(isPresented: $showSaveConfirmation, onDismiss: {
                if confirmedSave { save() }
            }) {
                SaveConfirmation(
                    title: needsKey ? "Before You Save" : "Lock Now?",
                    points: confirmationPoints,
                    footnote: needsKey ? "A Button profile is the easier choice for schedules." : nil,
                    confirmTitle: needsKey ? "Save Anyway" : "Save and Lock"
                ) {
                    confirmedSave = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if needsKey || schedule.isActive(at: Date()) {
                            showSaveConfirmation = true
                        } else {
                            save()
                        }
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var unlockMethod: UnlockMethod {
        profileManager.profiles.first { $0.id == schedule.profileID }?.unlockMethod ?? .key
    }

    /// A tag left at home means no way to unlock until the schedule ends.
    private var needsKey: Bool { unlockMethod == .key }

    private static let keyWarning = "This profile needs its tag or QR code to unlock early. If it locks while you're away from it, like on a trip, you'll stay locked until the schedule ends. A Button profile is the easier choice for schedules."

    private var confirmationPoints: [SaveConfirmation.Point] {
        var points: [SaveConfirmation.Point] = []
        if needsKey {
            points.append(.init(
                icon: "key.fill",
                title: "Unlocking early needs the tag",
                detail: "If it locks while you're away from your tag or QR code, like on a trip, you'll stay locked until the schedule ends. Turning the schedule off or deleting it won't unlock you either."
            ))
        }
        if let end = schedule.activeEnd(at: Date()) {
            points.append(.init(
                icon: "lock.fill",
                title: "Locks right away",
                detail: "It's already in its window, so Goose locks now until \(end.formatted(date: .omitted, time: .shortened))."
            ))
        }
        return points
    }

    private var unlockExplanation: String {
        switch unlockMethod {
        case .key: return "Locks automatically. To unlock early, scan one of this profile's tags or QR codes."
        case .timer: return "Locks automatically and stays locked until the schedule ends."
        case .button: return "Locks automatically. Tap the lock button to unlock early."
        }
    }

    private func save() {
        rules.save(schedule, profiles: profileManager.profiles)
        dismiss()
    }

    private func timeBinding(hour: WritableKeyPath<BlockSchedule, Int>, minute: WritableKeyPath<BlockSchedule, Int>) -> Binding<Date> {
        Binding {
            Calendar.current.date(bySettingHour: schedule[keyPath: hour], minute: schedule[keyPath: minute], second: 0, of: Date()) ?? Date()
        } set: { date in
            schedule[keyPath: hour] = Calendar.current.component(.hour, from: date)
            schedule[keyPath: minute] = Calendar.current.component(.minute, from: date)
        }
    }
}

// MARK: - Daily limits

struct DailyLimitsView: View {
    @EnvironmentObject private var rules: BlockRulesManager
    @EnvironmentObject private var profileManager: ProfileManager
    @State private var editing: DailyLimit?
    @State private var showLimitLocked = false

    var body: some View {
        List {
            Section {
                ForEach(rules.limits) { limit in
                    Button {
                        if rules.isLocked(limit) {
                            lockedLimitMessage = rules.needsKeyToLift(limit, profiles: profileManager.profiles)
                                ? "You've used up this limit for today. To unlock it for the rest of the day, tap the lock button on the main screen and scan this profile's tag or QR code."
                                : "You've used up this limit for today. To unlock it for the rest of the day, tap the lock button on the main screen."
                            showLimitLocked = true
                        } else {
                            editing = limit
                        }
                    } label: {
                        limitRow(limit)
                    }
                    .tint(.primary)
                    // A limit that's been reached stays until tomorrow.
                    .deleteDisabled(rules.isLocked(limit))
                }
                .onDelete { offsets in
                    for limit in offsets.map({ rules.limits[$0] }) {
                        rules.delete(limit, profiles: profileManager.profiles)
                    }
                }
                Button {
                    editing = DailyLimit(profileID: profileManager.currentProfile.id)
                } label: {
                    Label("Add a Daily Limit", systemImage: "plus")
                }
            } footer: {
                Text("Once a profile's apps have been used for the set time in total, they're blocked until midnight. A limit can't be changed on a day it's been reached.")
            }
        }
        .navigationTitle("Daily Limits")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Limit Reached", isPresented: $showLimitLocked) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(lockedLimitMessage)
        }
        .sheet(item: $editing) { limit in
            LimitEditor(limit: limit, isNew: !rules.limits.contains { $0.id == limit.id })
        }
    }

    @State private var lockedLimitMessage = ""

    private func limitRow(_ limit: DailyLimit) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(profileManager.profiles.first { $0.id == limit.profileID }?.name ?? "Deleted profile")
                    .font(.body.weight(.medium))
                Text("\(formatMinutes(limit.minutes)) a day")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if rules.isLiftedToday(limit) {
                    Label("Unlocked for today", systemImage: "lock.open.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
                if rules.isLocked(limit) {
                    Label("Reached today", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if !limit.isEnabled {
                Text("Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(limit.isEnabled ? 1 : 0.6)
        .padding(.vertical, 2)
    }
}

private struct LimitEditor: View {
    let isNew: Bool
    @EnvironmentObject private var rules: BlockRulesManager
    @EnvironmentObject private var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var limit: DailyLimit
    @State private var showSaveConfirmation = false
    @State private var confirmedSave = false

    init(limit: DailyLimit, isNew: Bool) {
        self.isNew = isNew
        _limit = State(initialValue: limit)
    }

    private var hours: Binding<Int> {
        Binding { limit.minutes / 60 } set: { limit.minutes = $0 * 60 + limit.minutes % 60 }
    }

    private var minutes: Binding<Int> {
        Binding { limit.minutes % 60 } set: { limit.minutes = (limit.minutes / 60) * 60 + $0 }
    }

    /// Hitting the limit away from the tag means staying locked until midnight.
    private var needsKey: Bool {
        profileManager.profiles.first { $0.id == limit.profileID }?.unlockMethod == .key
    }

    private func save() {
        rules.save(limit, profiles: profileManager.profiles)
        dismiss()
    }

    private var limitExplanation: String {
        let counts = "Counts the total time across all of the profile's apps and websites."
        switch profileManager.profiles.first(where: { $0.id == limit.profileID })?.unlockMethod ?? .key {
        case .key: return counts + " Once it's reached, Goose locks until midnight. Unlocking with this profile's tag or QR code turns the limit off for the rest of the day."
        case .timer, .button: return counts + " Once it's reached, Goose locks until midnight. Unlocking with the lock button turns the limit off for the rest of the day."
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ProfileChooser(selection: $limit.profileID)
                } footer: {
                    if needsKey {
                        Label("This profile needs its tag or QR code to unlock. If you hit the limit while you're away from it, like on a trip, you'll stay locked until midnight. A Button profile is the easier choice for daily limits.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    HStack(spacing: 0) {
                        Picker("Hours", selection: hours) {
                            ForEach(0..<24, id: \.self) { Text("\($0) hr").tag($0) }
                        }
                        Picker("Minutes", selection: minutes) {
                            ForEach(0..<60, id: \.self) { Text("\($0) min").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 150)
                } header: {
                    Text("Allowed Each Day")
                } footer: {
                    Text(limitExplanation)
                }

                Section {
                    Toggle("On", isOn: $limit.isEnabled)
                }

                if !isNew {
                    Section {
                        Button("Delete Limit", role: .destructive) {
                            rules.delete(limit, profiles: profileManager.profiles)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Daily Limit" : "Edit Daily Limit")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSaveConfirmation, onDismiss: {
                if confirmedSave { save() }
            }) {
                SaveConfirmation(
                    title: "Before You Save",
                    points: [.init(
                        icon: "key.fill",
                        title: "Unlocking needs the tag",
                        detail: "If you hit the limit while you're away from your tag or QR code, like on a trip, you'll stay locked until midnight. Turning the limit off or deleting it won't unlock you either."
                    )],
                    footnote: "A Button profile is the easier choice for daily limits.",
                    confirmTitle: "Save Anyway"
                ) {
                    confirmedSave = true
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if needsKey {
                            showSaveConfirmation = true
                        } else {
                            save()
                        }
                    }
                    .disabled(limit.minutes < 1)
                }
            }
        }
    }
}

// MARK: - Shared pieces

private struct ProfileChooser: View {
    @Binding var selection: UUID
    @EnvironmentObject private var profileManager: ProfileManager

    var body: some View {
        Picker("Profile", selection: $selection) {
            ForEach(profileManager.profiles) { profile in
                Label(profile.name, systemImage: profile.icon).tag(profile.id)
            }
        }
    }
}

private struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        HStack {
            // Starts on the user's first weekday, e.g. Monday in much of Europe.
            ForEach(orderedWeekdays, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isOn ? Color.white : .primary)
                        .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15)))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 4)
    }

    private var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }
}

func timeRange(_ schedule: BlockSchedule) -> String {
    let calendar = Calendar.current
    let start = calendar.date(bySettingHour: schedule.startHour, minute: schedule.startMinute, second: 0, of: Date()) ?? Date()
    let end = calendar.date(bySettingHour: schedule.endHour, minute: schedule.endMinute, second: 0, of: Date()) ?? Date()
    return "\(start.formatted(date: .omitted, time: .shortened)) to \(end.formatted(date: .omitted, time: .shortened))"
}

func daysSummary(_ weekdays: Set<Int>) -> String {
    switch weekdays {
    case Set(1...7): return "Every day"
    case [2, 3, 4, 5, 6]: return "Weekdays"
    case [1, 7]: return "Weekends"
    default:
        let symbols = Calendar.current.shortWeekdaySymbols
        let first = Calendar.current.firstWeekday
        let ordered = (0..<7).map { (first - 1 + $0) % 7 + 1 }.filter(weekdays.contains)
        return ordered.map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}

// MARK: - Save confirmation

/// Shown before saving a schedule or daily limit that can lock you somewhere
/// you can't easily unlock, like a tag profile away from its tag.
private struct SaveConfirmation: View {
    struct Point: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    let title: String
    let points: [Point]
    var footnote: String?
    let confirmTitle: String
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 360

    private let slate = Color(red: 0.231, green: 0.227, blue: 0.247)
    private var accent: Color { SkyPeriod.current(for: Date()).color }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title)
                .font(.system(size: 26, weight: .semibold, design: .serif))

            VStack(alignment: .leading, spacing: 16) {
                ForEach(points) { point in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: point.icon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.black)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(accent))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(point.title)
                                .font(.system(.headline, design: .rounded))
                            Text(point.detail)
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            if let footnote {
                Text(footnote)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }

            VStack(spacing: 10) {
                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(confirmTitle)
                        .font(.system(.headline, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(RoundedRectangle(cornerRadius: 16).fill(accent))
                }
                .buttonStyle(PressableButtonStyle())

                Button("Cancel") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .foregroundStyle(.white)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .environment(\.colorScheme, .dark)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(slate)
    }
}
