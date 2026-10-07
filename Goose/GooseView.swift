//
//  GooseView.swift
//  Goose
//
//  Originally by Oz Tamir.
//  Modified for Goose.
//

import SwiftUI
import CoreNFC
import SFSymbolsPicker
import FamilyControls
import ManagedSettings

struct GooseView: View {
    @EnvironmentObject private var appBlocker: AppBlocker
    @EnvironmentObject private var profileManager: ProfileManager
    @EnvironmentObject private var tagManager: TagManager
    @EnvironmentObject private var rules: BlockRulesManager
    @StateObject private var nfcReader = NFCReader()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("didFinishSetup") private var didFinishSetup = false

    @State private var showWrongTagAlert = false
    @State private var showTagMenu = false
    @State private var showTagResultAlert = false
    @State private var tagWriteSucceeded = false
    @State private var showTagManagement = false
    @State private var showScanChoice = false
    @State private var showQRScanner = false
    @State private var showTimerConfirm = false
    @State private var showTimerRunningAlert = false
    @State private var showNoTagsAlert = false
    @State private var showOnboarding = false
    @State private var showInfo = false
    @State private var pendingAddChoice: AddTagSheet.Choice?
    /// Set while scanning to unlock a reached daily limit instead of the lock.
    @State private var limitToLift: DailyLimit?
    @State private var limitToConfirm: DailyLimit?
    @State private var shownQRCode: GooseTag?
    @State private var editingProfile: Profile?
    @AppStorage(QuoteSettings.showKey) private var showQuotes = true
    @State private var reflection = Reflection.random()
    @State private var now = Date()
    @State private var tick = Date()

    private let clockTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var isBlocking: Bool {
        appBlocker.isBlocking
    }

    /// A reached daily limit counts as a lock on the main screen; unlocking
    /// it the profile's usual way turns it off for the rest of the day.
    private var reachedLimit: DailyLimit? {
        isBlocking ? nil : rules.reachedLimits().first
    }

    private var showsLocked: Bool { isBlocking || reachedLimit != nil }

    /// When a reached limit resets.
    private var midnight: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
    }

    private var profile: Profile { profileManager.currentProfile }

    /// The profile whose tags unlock the current lock. A schedule can lock a
    /// profile other than the selected one.
    private var keyProfile: Profile {
        if let limit = limitToLift, let owner = profileManager.profiles.first(where: { $0.id == limit.profileID }) {
            return owner
        }
        guard isBlocking, let id = appBlocker.lockedProfileID else { return profile }
        return profileManager.profiles.first { $0.id == id } ?? profile
    }

    private var skyPeriod: SkyPeriod { SkyPeriod.current(for: now) }

    private var canReadNFC: Bool { NFCNDEFReaderSession.readingAvailable }

    private var lockedClockString: String {
        let seconds: Int
        if let end = reachedLimit != nil ? midnight : appBlocker.blockEndDate {
            seconds = max(0, Int(end.timeIntervalSince(tick).rounded(.up)))
        } else if let start = appBlocker.blockStartDate {
            seconds = max(0, Int(tick.timeIntervalSince(start)))
        } else {
            seconds = 0
        }
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundLayer

                VStack(spacing: 0) {
                    ZStack {
                        HStack {
                            infoButton
                            Spacer()
                            createTagButton
                        }
                        lockButton
                    }
                    .frame(height: 50)
                    .padding(.horizontal, 28)
                    .padding(.top, 40)

                    // The goose stays put: the space above it is capped, so a
                    // longer quote or a banner only grows downward.
                    Spacer(minLength: 16)
                        .frame(maxHeight: 56)

                    Image("GooseMark")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 220, height: 220)
                        .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
                        .overlay(alignment: .top) {
                            if let ruleStatus {
                                Label(ruleStatus.text, systemImage: ruleStatus.icon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .fixedSize()
                                    .offset(y: -44)
                            }
                        }

                    if showQuotes, let reflection {
                        ReflectionCard(reflection: reflection)
                            .padding(.horizontal, 28)
                            .padding(.top, 18)
                    }

                    Spacer(minLength: 16)

                    // The profiles panel keeps its space while locked so nothing
                    // above it shifts; it slides away and the clock fades in.
                    ZStack {
                        ProfilesPicker(profileManager: profileManager)
                            .offset(y: showsLocked ? 320 : 0)
                            .opacity(showsLocked ? 0 : 1)
                            .allowsHitTesting(!showsLocked)
                        if showsLocked {
                            lockedStatusPanel
                                .transition(.opacity)
                        }
                    }
                }
            }
            .alert(isPresented: $showWrongTagAlert) {
                Alert(
                    title: Text("Wrong Tag"),
                    message: Text(tagManager.hasDedicatedTag(profileID: keyProfile.id)
                        ? "\"\(keyProfile.name)\" has a dedicated tag or QR code. Only that one can lock or unlock it."
                        : "Goose doesn't recognize that one. You can make a new tag or QR code with the + button."),
                    dismissButton: .default(Text("OK"))
                )
            }
            .sheet(isPresented: $showTagMenu, onDismiss: runPendingAddChoice) {
                AddTagSheet(
                    profileName: profile.name,
                    showsDedicatedOption: profileManager.profiles.count > 1,
                    existingCount: tagManager.tags.count
                ) { choice in
                    pendingAddChoice = choice
                }
            }
            .confirmationDialog("Scan", isPresented: $showScanChoice) {
                Button("Scan NFC Tag") { scanNFC() }
                Button("Scan QR Code") { showQRScanner = true }
                Button("Cancel", role: .cancel) { }
            }
            .confirmationDialog("Start Timer", isPresented: $showTimerConfirm, titleVisibility: .visible) {
                Button("Block for \(formatMinutes(profile.timerMinutes))") { lock() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You can't unlock early. Apps unblock on their own when the timer ends.")
            }
            .alert("Timer Running", isPresented: $showTimerRunningAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(appBlocker.blockEndDate.map { "Your apps unblock at \($0.formatted(date: .omitted, time: .shortened))." } ?? "")
            }
            .confirmationDialog(
                "Unlock for the Rest of Today?",
                isPresented: Binding(get: { limitToConfirm != nil }, set: { if !$0 { limitToConfirm = nil } }),
                titleVisibility: .visible
            ) {
                Button("Unlock for Today") {
                    if let limit = limitToConfirm {
                        rules.liftForToday(limit)
                        Haptics.notify(.success)
                    }
                }
                Button("Keep Blocked", role: .cancel) { }
            } message: {
                Text("You've used today's limit. The apps unblock until midnight, then the limit starts again tomorrow.")
            }
            .alert("No Tags Yet", isPresented: $showNoTagsAlert) {
                Button("Make One") { showTagMenu = true }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This profile unlocks with a tag or QR code. Make one first, or switch the profile to Timer or Button.")
            }
            .alert("Tag Creation", isPresented: $showTagResultAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(tagWriteSucceeded ? "Goose tag created successfully!" : "Failed to create Goose tag. Please try again.")
            }
            .sheet(isPresented: $showTagManagement) {
                TagManagementView()
            }
            .sheet(isPresented: $showInfo, onDismiss: { reflection = .random() }) {
                InfoView()
            }
            .sheet(isPresented: $showQRScanner) {
                QRScanSheet { code in handleScanned(code) }
            }
            .sheet(item: $shownQRCode) { tag in
                QRCodeSheet(tag: tag)
            }
            .sheet(item: $editingProfile) { profile in
                ProfileFormView(profile: profile, profileManager: profileManager) {
                    editingProfile = nil
                }
            }
            .fullScreenCover(isPresented: $showOnboarding) {
                OnboardingView(profileManager: profileManager) { firstTag in
                    didFinishSetup = true
                    showOnboarding = false
                    // Let the cover finish dismissing before showing NFC or a sheet.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        switch firstTag {
                        case .nfc: createNFCTag(assignedProfileID: nil)
                        case .qr: createQRCode(assignedProfileID: nil)
                        case nil: break
                        }
                    }
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: showsLocked)
        .onReceive(clockTimer) { date in
            now = date
            rules.enforceSchedules(at: date)
            appBlocker.refresh()
        }
        .onReceive(secondTimer) { date in
            tick = date
            if let end = appBlocker.blockEndDate, end <= date {
                appBlocker.refresh()
            }
        }
        .onReceive(profileManager.$profiles) { profiles in
            rules.sync(profiles: profiles)
            appBlocker.refresh()
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            rules.sync(profiles: profileManager.profiles)
            appBlocker.refresh()
            handlePendingLockAction()
        }
        .onReceive(NotificationCenter.default.publisher(for: GooseShared.lockActionRequested)) { _ in
            handlePendingLockAction()
        }
        .onAppear {
            startSetupIfNeeded()
            handlePendingLockAction()
        }
    }

    /// The schedule behind the current lock, or a daily limit that's been
    /// hit. `now` ticks every minute, which keeps this current.
    private var ruleStatus: (text: String, icon: String)? {
        if isBlocking, let id = appBlocker.lockingScheduleID,
           let schedule = rules.schedules.first(where: { $0.id == id }),
           let end = schedule.activeEnd(at: now) {
            let name = schedule.name.isEmpty ? "Schedule" : schedule.name
            return ("\(name) until \(end.formatted(date: .omitted, time: .shortened))", "calendar")
        }
        if let limit = reachedLimit {
            let name = profileManager.profiles.first { $0.id == limit.profileID }?.name ?? "Daily"
            return ("\(name) limit reached for today", "hourglass")
        }
        return nil
    }

    private func startSetupIfNeeded() {
        guard !didFinishSetup else { return }
        if profileManager.profiles.count == 1 && profile.blockedCount == 0 {
            showOnboarding = true
        } else {
            didFinishSetup = true
        }
    }

    /// A request from the widget or Action Button can arrive before or after
    /// the app is fully in the foreground, so both paths check for it.
    private func handlePendingLockAction() {
        guard scenePhase == .active, GooseShared.consumePendingLockAction() else { return }
        // NFC sessions started while the app is still coming forward are
        // invalidated immediately.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            performLockAction()
        }
    }

    // MARK: - Locking

    /// What the lock button, widget and Action Button do, depending on how the
    /// profile unlocks.
    private func performLockAction() {
        limitToLift = nil
        if isBlocking {
            switch appBlocker.activeMethod {
            case .key: scanForKey()
            case .timer: showTimerRunningAlert = true
            case .button: unlock()
            }
            return
        }
        if let limit = reachedLimit {
            unlockForToday(limit)
            return
        }

        guard profile.blockedCount > 0 else {
            editingProfile = profile
            return
        }
        switch profile.unlockMethod {
        case .key:
            if tagManager.tags.isEmpty {
                showNoTagsAlert = true
            } else {
                scanForKey()
            }
        case .timer: showTimerConfirm = true
        case .button: lock()
        }
    }

    private func scanForKey() {
        let hasNFC = canReadNFC && tagManager.tags.contains { $0.kind == .nfc }
        let hasQR = tagManager.tags.contains { $0.kind == .qr }
        switch (hasNFC, hasQR) {
        case (true, true): showScanChoice = true
        case (true, false): scanNFC()
        case (false, true): showQRScanner = true
        case (false, false): showNoTagsAlert = true
        }
    }

    private func scanNFC() {
        nfcReader.scan { payload in handleScanned(payload) }
    }

    /// Tag or QR profiles scan, Button profiles just unlock, and Timer
    /// profiles (which normally can't end early) confirm first.
    private func unlockForToday(_ limit: DailyLimit) {
        switch profileManager.profiles.first(where: { $0.id == limit.profileID })?.unlockMethod ?? .key {
        case .key:
            limitToLift = limit
            scanForKey()
        case .button:
            rules.liftForToday(limit)
            Haptics.notify(.success)
            reflection = .random()
        case .timer:
            limitToConfirm = limit
        }
    }

    private func handleScanned(_ code: String) {
        guard tagManager.isValidScan(code: code, for: keyProfile) else {
            Haptics.notify(.error)
            showWrongTagAlert = true
            return
        }
        if let limit = limitToLift {
            limitToLift = nil
            rules.liftForToday(limit)
            Haptics.notify(.success)
            return
        }
        if isBlocking {
            unlock()
        } else {
            lock()
        }
    }

    private func lock() {
        appBlocker.lock(profile, accentColorName: skyPeriod.rawValue)
        Haptics.notify(.success)
        reflection = .random()
    }

    private func unlock() {
        // One unlock frees everything for that profile, including a limit
        // reached while it was locked.
        let unlocked = keyProfile.id
        appBlocker.unlock()
        for limit in rules.reachedLimits() where limit.profileID == unlocked {
            rules.liftForToday(limit)
        }
        Haptics.notify(.success)
        reflection = .random()
    }

    // MARK: - Locked status panel

    private var lockedStatusPanel: some View {
        VStack(spacing: 4) {
            Text(lockedClockString)
                .font(.system(size: 52, weight: .medium, design: .serif))
                .monospacedDigit()
            if reachedLimit != nil {
                Text("Limit reached · Unlocks at \(midnight.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.8)
            } else if let end = appBlocker.blockEndDate {
                Text("Unlocks at \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 13, weight: .semibold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
        .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 2)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 28)
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundLayer: some View {
        // Same slate gray as the app icon's background, so the two match.
        Color(red: 0.231, green: 0.227, blue: 0.247)
            .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: skyPeriod)
    }

    // MARK: - Lock button

    private var lockButtonIcon: String {
        guard isBlocking else { return reachedLimit != nil ? "lock.fill" : "lock.open.fill" }
        return appBlocker.activeMethod == .timer ? "hourglass" : "lock.fill"
    }

    private var lockButton: some View {
        Button {
            Haptics.impact(.medium)
            performLockAction()
        } label: {
            Image(systemName: lockButtonIcon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(Circle().fill(showsLocked ? Color(white: 0.22) : skyPeriod.color))
                .shadow(color: (showsLocked ? Color.black : skyPeriod.color).opacity(0.4), radius: 14, x: 0, y: 6)
        }
        .buttonStyle(PressableButtonStyle())
        .animation(.easeInOut(duration: 0.6), value: skyPeriod)
    }

    /// Runs after the add sheet has closed, so the NFC scanner or the next
    /// sheet doesn't collide with the dismissal.
    private func runPendingAddChoice() {
        guard let choice = pendingAddChoice else { return }
        pendingAddChoice = nil
        switch choice {
        case .nfc(let dedicated): createNFCTag(assignedProfileID: dedicated ? profile.id : nil)
        case .qr(let dedicated): createQRCode(assignedProfileID: dedicated ? profile.id : nil)
        case .manage: showTagManagement = true
        }
    }

    // MARK: - Top buttons

    private var infoButton: some View {
        Button {
            showInfo = true
        } label: {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel("Menu")
    }

    private var createTagButton: some View {
        Button {
            showTagMenu = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func newTagName(kind: GooseTag.Kind, assignedProfileID: UUID?) -> String {
        let noun = kind == .nfc ? "Tag" : "QR Code"
        if let assignedProfileID, let owner = profileManager.profiles.first(where: { $0.id == assignedProfileID }) {
            return "\(owner.name) \(noun)"
        }
        return "\(noun) \(tagManager.tags.filter { $0.isGeneral && $0.kind == kind }.count + 1)"
    }

    private func createNFCTag(assignedProfileID: UUID?) {
        let newTag = GooseTag(name: newTagName(kind: .nfc, assignedProfileID: assignedProfileID), assignedProfileID: assignedProfileID)
        nfcReader.write(newTag.code) { success in
            if success {
                tagManager.addTag(newTag)
            }
            tagWriteSucceeded = success
            showTagResultAlert = true
        }
    }

    private func createQRCode(assignedProfileID: UUID?) {
        let newTag = GooseTag(name: newTagName(kind: .qr, assignedProfileID: assignedProfileID), assignedProfileID: assignedProfileID, kind: .qr)
        tagManager.addTag(newTag)
        shownQRCode = newTag
    }
}

/// A plain Google Shopping search, not an affiliate link: no store pays for
/// placement and nobody earns a cut.
let nfcTagShoppingURL = URL(string: "https://www.google.com/search?tbm=shop&q=NTAG213+NFC+stickers")!

func formatMinutes(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    let rest = minutes % 60
    let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
    return rest == 0 ? hourText : "\(hourText) \(rest) min"
}

// MARK: - Shared UI helpers

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}

// MARK: - Reflections

struct Reflection: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let attribution: String?

    /// Drawn from the built-in quotes and the user's own, per their settings.
    /// Nil when both are turned off or empty.
    static func random() -> Reflection? {
        let custom = QuoteSettings.customQuotes.map { Reflection(text: $0.text, attribution: $0.attribution) }
        return ((QuoteSettings.includeBuiltIn ? all : []) + custom).randomElement()
    }

    static let all: [Reflection] = [
        // Greek myth, retold
        Reflection(text: "Sisyphus reaches the top of the hill again and again. Somewhere in the climbing, not the summit, he finds he is free.", attribution: "after the myth of Sisyphus"),
        Reflection(text: "Narcissus drowned chasing his own reflection. Look up. The world is wider than the glass in your hand.", attribution: "after the myth of Narcissus"),
        Reflection(text: "Icarus flew because he dared to. He fell because he forgot the sea was still down there, waiting to catch him.", attribution: "after the myth of Icarus"),
        Reflection(text: "Prometheus stole fire and paid for it daily, and never once wished he hadn't given it away.", attribution: "after the myth of Prometheus"),
        Reflection(text: "Odysseus had himself tied to the mast, not because he was weak, but because he knew exactly how strong the song would be.", attribution: "after the Odyssey"),
        Reflection(text: "The Hydra grew two heads for every one that was hacked away blindly. It stopped only when someone paused to think.", attribution: "after the myth of the Hydra"),
        Reflection(text: "The phoenix does not fear the fire. It has done this before, and it always knows how to begin again.", attribution: "after the myth of the phoenix"),
        Reflection(text: "Persephone spends half the year in the dark and still brings spring with her every time she returns.", attribution: "after the myth of Persephone"),
        Reflection(text: "Atlas holds up the sky, but only because, one ordinary day, he chose to stand and keep standing.", attribution: "after the myth of Atlas"),
        Reflection(text: "Theseus found his way out of the labyrinth by a thread he laid down himself on the way in. You are already leaving yourself a way back.", attribution: "after the myth of Theseus"),
        Reflection(text: "Orpheus got everything he wanted back, on one condition: don't look back to check. He looked. Keep walking. Don't check.", attribution: "after the myth of Orpheus"),
        Reflection(text: "Pandora opened the one jar she was told to leave alone. When everything terrible had flown out, the last thing left inside was hope.", attribution: "after the myth of Pandora"),
        Reflection(text: "Midas got exactly what he asked for. Everything he touched turned to gold, including his dinner, including his daughter. Some cravings are like that. Choose carefully what you reach for.", attribution: "after the myth of Midas"),

        // Stoic philosophy
        Reflection(text: "You have power over your mind, not outside events. Realize this, and you will find strength.", attribution: "Marcus Aurelius"),
        Reflection(text: "It is not what happens to you, but how you react to it, that matters.", attribution: "Epictetus"),
        Reflection(text: "We suffer more often in imagination than in reality.", attribution: "Seneca"),
        Reflection(text: "No man steps in the same river twice, for it's not the same river and he's not the same man.", attribution: "Heraclitus"),
        Reflection(text: "The unexamined life is not worth living.", attribution: "Socrates"),
        Reflection(text: "First say to yourself what you would be, and then do what you have to do.", attribution: "Epictetus"),
        Reflection(text: "Waste no more time arguing about what a good person should be. Be one.", attribution: "Marcus Aurelius"),
        Reflection(text: "He who is brave is free.", attribution: "Seneca"),
        Reflection(text: "Difficulties strengthen the mind, as labor does the body.", attribution: "Seneca"),
        Reflection(text: "The impediment to action advances action. What stands in the way becomes the way.", attribution: "Marcus Aurelius"),
        Reflection(text: "It is not that we have a short time to live, but that we waste a lot of it.", attribution: "Seneca"),
        Reflection(text: "Begin at once to live, and count each separate day as a separate life.", attribution: "Seneca"),
        Reflection(text: "You act like mortals in all that you fear, and like immortals in all that you desire.", attribution: "Seneca"),
        Reflection(text: "It is not death that a person should fear. They should fear never beginning to truly live.", attribution: "Marcus Aurelius"),

        // Absurdism
        Reflection(text: "The universe was never going to explain itself to you. That was never the deal. Get up and make the coffee anyway.", attribution: nil),
        Reflection(text: "You can spend your life demanding the world make sense, or you can spend it living in the world you actually have. Only one of those is a life.", attribution: nil),
        Reflection(text: "Nothing you do today will matter in a thousand years. It can still matter today. That's allowed to be enough.", attribution: nil),
        Reflection(text: "The search for a reason can become its own kind of trap. Sometimes the answer is just: because it's Tuesday, and you're still here, and that's worth showing up for.", attribution: nil),
        Reflection(text: "There may be no grand meaning waiting at the end of this. Push the rock anyway. Something in the pushing is still yours.", attribution: nil),

        // Life is short
        Reflection(text: "You will not get this hour back. Spend some of it looking at an actual sky.", attribution: nil),
        Reflection(text: "Nobody at the end of their life has ever wished they had checked one more notification.", attribution: nil),
        Reflection(text: "The days are long, but there are fewer of them left than you think. Spend a few more of them awake.", attribution: nil),
        Reflection(text: "You keep waiting for the version of your life where you finally pay attention to it. It's this one.", attribution: nil),

        // Modern reflections
        Reflection(text: "You do not have to be perfect today. You only have to be a little more here than you were yesterday.", attribution: nil),
        Reflection(text: "The craving is loud, but it is not you. Sit still long enough and you'll hear it get tired before you do.", attribution: nil),
        Reflection(text: "Somewhere above you, birds are flying home again, exactly on time, the way they always do. The world keeps its promises even on days you doubt yours.", attribution: nil),
        Reflection(text: "Every morning the sun forgets what you did wrong yesterday. Try to do the same.", attribution: nil),
        Reflection(text: "Strength isn't never falling. It's the quiet, unglamorous act of standing back up one more time than you fell.", attribution: nil),
        Reflection(text: "The river doesn't fight the rock. It just keeps moving, and after long enough, there is no rock left.", attribution: nil),
        Reflection(text: "You are allowed to begin again as many times as you need to. Nothing is keeping score but you.", attribution: nil),
        Reflection(text: "The part of you that wants to change is not weaker than the part that wants to give in. It is only quieter. Let it speak.", attribution: nil),
        Reflection(text: "Life is still beautiful on the days you can't see it. Especially then.", attribution: nil),
        Reflection(text: "One good hour can undo the pull of a bad one. You only ever need to get through the next one.", attribution: nil),
        Reflection(text: "The urge will pass whether or not you give in to it. That's the part no one tells you.", attribution: nil),
        Reflection(text: "You are not behind. There is no schedule. There is only the next right thing.", attribution: nil),
        Reflection(text: "Put the phone down, and the world does not stop needing you in it.", attribution: nil),
        Reflection(text: "Nothing that is truly good for you asks to be checked every six minutes.", attribution: nil),
        Reflection(text: "Boredom is not an emergency. Sit with it a while. It usually has something quieter to say underneath.", attribution: nil),
        Reflection(text: "In a flock of geese, no single bird leads the whole way. They take turns cutting the wind so the rest can rest. You do not have to carry this by yourself either.", attribution: nil),
        Reflection(text: "Geese fly thousands of miles and still find their way back to the exact same pond. You have not lost your way. You are just still in the air.", attribution: nil),
        Reflection(text: "A goose that strays from the formation feels the drag immediately and works its way back in. Notice the drag. Let it be information, not shame.", attribution: nil),
        Reflection(text: "Your attention was the one thing that was always actually yours. You are allowed to ask for it back.", attribution: nil),
        Reflection(text: "Somewhere, a hundred people were paid to make this hard to put down. You get to be the person who put it down anyway.", attribution: nil),
        Reflection(text: "The version of you that scrolls at 2am and the version of you that wants a good life are the same person. Be gentle getting them back on speaking terms.", attribution: nil),
        Reflection(text: "You do not need a better reason to stop than the fact that you are tired of feeling this way.", attribution: nil),

        // Belonging
        Reflection(text: "You do not have to have your life in order to be allowed to keep living it.", attribution: nil),
        Reflection(text: "Whatever last night looked like, the morning does not make you apologize before it lets the light in.", attribution: nil),
        Reflection(text: "You are allowed to want simple things, like quiet, rest or a walk outside, without treating the wanting as another failure.", attribution: nil),
        Reflection(text: "The mountains did not stop being mountains while you were struggling. Nothing out there was waiting for you to get it right first.", attribution: nil),
        Reflection(text: "Loneliness feels like proof you don't belong anywhere. It isn't. It's just weather passing through. It was never a verdict.", attribution: nil),
        Reflection(text: "You don't need a clean record to be let back in. Just show up. Nobody was guarding the door.", attribution: nil),
        Reflection(text: "Nothing out there is keeping a list of your worst days. You are allowed to put yours down too.", attribution: nil),
        Reflection(text: "You were never on probation with the world. It kept a place for you through all of it.", attribution: nil),
    ]
}

struct ReflectionCard: View {
    let reflection: Reflection

    var body: some View {
        VStack(spacing: 16) {
            Text("“\(reflection.text)”")
                .font(.system(.title2, design: .serif))
                .italic()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
                .shadow(color: .black.opacity(0.5), radius: 10, x: 0, y: 2)

            if let attribution = reflection.attribution {
                Text(attribution.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.9), radius: 3, x: 0, y: 1)
            }
        }
        .id(reflection.id)
        .transition(.opacity.combined(with: .scale(scale: 0.97)))
        .animation(.easeInOut(duration: 0.4), value: reflection.id)
        .padding(.horizontal, 22)
    }
}

// MARK: - Tag management

struct TagManagementView: View {
    @EnvironmentObject private var tagManager: TagManager
    @EnvironmentObject private var profileManager: ProfileManager
    @Environment(\.dismiss) private var dismiss
    @State private var shownQRCode: GooseTag?

    var body: some View {
        NavigationView {
            List {
                if tagManager.tags.isEmpty {
                    Text("Nothing here yet. Use the + button on the main screen to write a tag or make a QR code.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(tagManager.tags) { tag in
                        Button {
                            if tag.kind == .qr { shownQRCode = tag }
                        } label: {
                            row(for: tag)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            tagManager.deleteTag(withId: tagManager.tags[index].id)
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Any tag or QR code can lock or unlock a profile, unless that profile has a dedicated one (marked with a key). Then only its dedicated ones work. Tap a QR code to view or print it again.")
                        .foregroundColor(.secondary)
                    if NFCNDEFReaderSession.readingAvailable {
                        Link("Need NFC tags? Search for NTAG213 stickers (no affiliate link)", destination: nfcTagShoppingURL)
                    }
                }
                .font(.footnote)
                .padding()
            }
            .navigationTitle("Tags and QR Codes")
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .sheet(item: $shownQRCode) { tag in
                QRCodeSheet(tag: tag)
            }
        }
    }

    private func row(for tag: GooseTag) -> some View {
        HStack(spacing: 12) {
            Image(systemName: tag.kind == .qr ? "qrcode" : "wave.3.right")
                .font(.system(size: 18))
                .frame(width: 28)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(tag.name)
                    .font(.body.weight(.medium))
                if let profileID = tag.assignedProfileID,
                   let owner = profileManager.profiles.first(where: { $0.id == profileID }) {
                    Label("Dedicated to \"\(owner.name)\"", systemImage: "key.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("Works on any profile without a dedicated one")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            if tag.kind == .qr {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}
