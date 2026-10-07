import SwiftUI
import CoreNFC
import FamilyControls

/// First launch: pick what to block and how to unlock, without having to
/// learn about profiles. Everything lands in the starting profile.
struct OnboardingView: View {
    @EnvironmentObject private var appBlocker: AppBlocker
    @ObservedObject var profileManager: ProfileManager
    /// Called with the kind of first tag to make, or nil to skip it.
    let onFinish: (GooseTag.Kind?) -> Void

    private enum Step {
        case apps, unlock, firstTag
    }

    @State private var step = Step.apps
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var method = UnlockMethod.key
    @State private var timerMinutes = 30

    private var selectedCount: Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    var body: some View {
        ZStack {
            Color(red: 0.231, green: 0.227, blue: 0.247)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image("GooseMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                    .padding(.top, 48)

                Spacer(minLength: 24)

                switch step {
                case .apps: appsStep
                case .unlock: unlockStep
                case .firstTag: firstTagStep
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 28)
            .foregroundStyle(.white)
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .sheet(isPresented: $showPicker) {
            NavigationView {
                FamilyActivityPicker(selection: $selection)
                    .navigationTitle("Choose Apps")
                    .navigationBarItems(trailing: Button("Done") { showPicker = false })
            }
        }
    }

    // MARK: Steps

    private var appsStep: some View {
        VStack(spacing: 20) {
            heading("What do you want to block?", "Pick the apps, categories and websites that pull you in. You can change this any time.")

            if appBlocker.isAuthorized {
                primaryButton(selectedCount == 0 ? "Choose Apps" : "\(selectedCount) Selected · Change") {
                    showPicker = true
                }
                .opacity(selectedCount == 0 ? 1 : 0.85)
            } else {
                primaryButton("Allow Screen Time Access") {
                    Task { await appBlocker.requestAuthorization() }
                }
                Text("Goose uses Screen Time to block apps. Apple never shows Goose which apps you pick.")
                    .font(.footnote)
                    .opacity(0.7)
                    .multilineTextAlignment(.center)
            }

            if selectedCount > 0 {
                primaryButton("Continue", filled: true) { step = .unlock }
            }
        }
    }

    private var unlockStep: some View {
        VStack(spacing: 14) {
            heading("How do you want to unlock?", nil)

            ForEach(UnlockMethod.allCases) { option in
                Button {
                    method = option
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: option.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(option.label)
                                .font(.system(.headline, design: .rounded))
                            Text(UnlockMethodSection.explanation(for: option))
                                .font(.footnote)
                                .opacity(0.75)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(method == option ? 0.16 : 0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(.white.opacity(method == option ? 0.6 : 0), lineWidth: 1.5)
                    )
                }
                .buttonStyle(.plain)
            }

            if method == .timer {
                Picker("Block for", selection: $timerMinutes) {
                    ForEach(Profile.timerChoices, id: \.self) { minutes in
                        Text(formatMinutes(minutes)).tag(minutes)
                    }
                }
                .pickerStyle(.menu)
                .tint(.white)
            }

            primaryButton(method == .key ? "Continue" : "Done", filled: true) {
                saveChoices()
                if method == .key {
                    step = .firstTag
                } else {
                    onFinish(nil)
                }
            }
            .padding(.top, 6)
        }
    }

    private var firstTagStep: some View {
        VStack(spacing: 20) {
            heading("Make your first key", "Keep it somewhere you'd have to get up to reach. Any NTAG sticker or card works for NFC, or print a QR code.")

            if NFCNDEFReaderSession.readingAvailable {
                primaryButton("Write an NFC Tag", filled: true) { onFinish(.nfc) }
            }
            primaryButton("Make a QR Code", filled: !NFCNDEFReaderSession.readingAvailable) { onFinish(.qr) }
            Button("Later") { onFinish(nil) }
                .font(.subheadline.weight(.medium))
                .opacity(0.8)
            if NFCNDEFReaderSession.readingAvailable {
                Link("Don't have tags? Find some (no affiliate link)", destination: nfcTagShoppingURL)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
        }
    }

    // MARK: Pieces

    private func heading(_ title: String, _ subtitle: String?) -> some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .opacity(0.75)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.bottom, 8)
    }

    private func primaryButton(_ title: String, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .foregroundStyle(filled ? Color.black : .white)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(filled ? AnyShapeStyle(SkyPeriod.current(for: Date()).color) : AnyShapeStyle(.white.opacity(0.12)))
                )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func saveChoices() {
        profileManager.updateProfile(
            id: profileManager.currentProfile.id,
            appTokens: selection.applicationTokens,
            categoryTokens: selection.categoryTokens,
            webDomainTokens: selection.webDomainTokens,
            unlockMethod: method,
            timerMinutes: timerMinutes
        )
    }
}
