import SwiftUI
import AVFoundation
import VisionKit
import CoreImage.CIFilterBuiltins

enum QRCode {
    /// A white card with the QR code and the tag's name under it, sized for printing.
    static func printableImage(code: String, title: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(code.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 20, y: 20)),
              let qr = CIContext().createCGImage(output, from: output.extent) else { return nil }

        let padding: CGFloat = 80
        let labelHeight: CGFloat = 120
        let qrSize = CGFloat(qr.width)
        let size = CGSize(width: qrSize + padding * 2, height: qrSize + padding * 2 + labelHeight)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            // Keep the modules crisp instead of blurring them when drawn.
            context.cgContext.interpolationQuality = .none
            UIImage(cgImage: qr).draw(in: CGRect(x: padding, y: padding, width: qrSize, height: qrSize))

            let label = NSAttributedString(string: "Goose · \(title)", attributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .semibold),
                .foregroundColor: UIColor.black,
            ])
            let labelSize = label.size()
            label.draw(at: CGPoint(x: (size.width - labelSize.width) / 2, y: padding + qrSize + (labelHeight - labelSize.height) / 2))
        }
    }
}

struct QRCodeSheet: View {
    let tag: GooseTag
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if let image = QRCode.printableImage(code: tag.code, title: tag.name) {
                    Image(uiImage: image)
                        .resizable()
                        .interpolation(.none)
                        .scaledToFit()
                        .frame(maxWidth: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    ShareLink(item: Image(uiImage: image), preview: SharePreview(tag.name, image: Image(uiImage: image))) {
                        Label("Save or Print", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: 280)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Text("Print it, or keep it on another device, somewhere you'd have to get up to reach. A phone can't scan a code on its own screen.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            .navigationTitle(tag.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct QRScanSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cameraAllowed: Bool?

    var body: some View {
        NavigationStack {
            Group {
                if !DataScannerViewController.isSupported {
                    ContentUnavailableView("Can't Scan Here", systemImage: "qrcode.viewfinder", description: Text("This device can't scan QR codes."))
                } else if cameraAllowed == false {
                    ContentUnavailableView("Camera Access Needed", systemImage: "camera", description: Text("Allow camera access for Goose in Settings to scan QR codes."))
                } else if cameraAllowed == true {
                    QRScannerView { code in
                        onCode(code)
                        dismiss()
                    }
                    .ignoresSafeArea()
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Scan QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            cameraAllowed = await AVCaptureDevice.requestAccess(for: .video)
        }
    }
}

private struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if !scanner.isScanning {
            try? scanner.startScanning()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCode: onCode)
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var reported = false

        init(onCode: @escaping (String) -> Void) {
            self.onCode = onCode
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            // Each report toggles the block, so only the first code counts.
            guard !reported else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    reported = true
                    dataScanner.stopScanning()
                    onCode(payload)
                    return
                }
            }
        }
    }
}
