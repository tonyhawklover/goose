import SwiftUI
import CoreNFC

/// What the + button opens: make an NFC tag or QR code, manage existing ones,
/// or find tags to buy.
struct AddTagSheet: View {
    enum Choice {
        case nfc(dedicated: Bool)
        case qr(dedicated: Bool)
        case manage
    }

    let profileName: String
    let showsDedicatedOption: Bool
    let existingCount: Int
    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var dedicated = false
    @State private var contentHeight: CGFloat = 420

    private let slate = Color(red: 0.231, green: 0.227, blue: 0.247)
    private var accent: Color { SkyPeriod.current(for: Date()).color }
    private var canReadNFC: Bool { NFCNDEFReaderSession.readingAvailable }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a Key")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                Text("Tags and QR codes lock and unlock your profiles.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
            }

            HStack(spacing: 12) {
                card(
                    icon: "wave.3.right",
                    title: "NFC Tag",
                    detail: canReadNFC ? "Write to a sticker or card" : "Needs an iPhone with NFC",
                    enabled: canReadNFC
                ) {
                    choose(.nfc(dedicated: dedicated))
                }
                card(
                    icon: "qrcode",
                    title: "QR Code",
                    detail: "Print it or keep it on another device",
                    enabled: true
                ) {
                    choose(.qr(dedicated: dedicated))
                }
            }

            if showsDedicatedOption {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Works with", selection: $dedicated) {
                        Text("Any profile").tag(false)
                        Text("Only \u{201C}\(profileName)\u{201D}").tag(true)
                    }
                    .pickerStyle(.segmented)

                    Text(dedicated
                         ? "A dedicated key. Once \u{201C}\(profileName)\u{201D} has one, only its dedicated keys can lock or unlock it."
                         : "Works on every profile that doesn't have a dedicated key.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                row(icon: "list.bullet", title: "Manage Tags and QR Codes", trailing: existingCount > 0 ? "\(existingCount)" : nil, systemTrailing: "chevron.right") {
                    choose(.manage)
                }
                if canReadNFC {
                    Divider().overlay(.white.opacity(0.1)).padding(.leading, 44)
                    row(icon: "cart", title: "Get NFC Tags", trailing: nil, systemTrailing: "arrow.up.right") {
                        openURL(nfcTagShoppingURL)
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 16).fill(.white.opacity(0.06)))

            if canReadNFC {
                Text("Get NFC Tags is a plain Google Shopping search. No affiliate links, so nobody earns anything from it.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, -12)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 12)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: dedicated)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        .presentationBackground(slate)
    }

    private func choose(_ choice: Choice) {
        Haptics.impact(.light)
        onChoose(choice)
        dismiss()
    }

    private func card(icon: String, title: String, detail: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(enabled ? accent : Color.white.opacity(0.25)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(.headline, design: .rounded))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 20).fill(.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.08), lineWidth: 1))
            .opacity(enabled ? 1 : 0.5)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!enabled)
    }

    private func row(icon: String, title: String, trailing: String?, systemTrailing: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                    .foregroundStyle(.white.opacity(0.7))
                Text(title)
                    .font(.body)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Image(systemName: systemTrailing)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
