import SwiftUI
import VisionKit

struct DataScannerRepresentable: UIViewControllerRepresentable {
    @Binding var recognizedItems: [RecognizedItem]
    let onItemTapped: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [
                .text(languages: ["en"]),
                .barcode(symbologies: [.qr, .ean13, .code128, .pdf417])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        Task { @MainActor in try? scanner.startScanning() }
        return scanner
    }

    func updateUIViewController(_: DataScannerViewController, context _: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator _: Coordinator) {
        controller.stopScanning()
    }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let parent: DataScannerRepresentable

        init(parent: DataScannerRepresentable) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            switch item {
            case .text(let text): parent.onItemTapped(text.transcript)
            case .barcode(let barcode):
                if let payload = barcode.payloadStringValue { parent.onItemTapped(payload) }
            @unknown default: break
            }
        }

        func dataScanner(_: DataScannerViewController, didAdd _: [RecognizedItem], allItems: [RecognizedItem]) {
            parent.recognizedItems = allItems
        }

        func dataScanner(_: DataScannerViewController, didUpdate _: [RecognizedItem], allItems: [RecognizedItem]) {
            parent.recognizedItems = allItems
        }

        func dataScanner(_: DataScannerViewController, didRemove _: [RecognizedItem], allItems: [RecognizedItem]) {
            parent.recognizedItems = allItems
        }
    }
}

struct HazardScannerView: View {
    @Environment(\.dismiss) private var dismiss
    let onTextSelected: (String) -> Void

    @State private var recognizedItems: [RecognizedItem] = []

    var body: some View {
        if DataScannerViewController.isSupported, DataScannerViewController.isAvailable {
            ZStack(alignment: .bottom) {
                DataScannerRepresentable(recognizedItems: $recognizedItems, onItemTapped: { text in
                    onTextSelected(text)
                    dismiss()
                })
                .ignoresSafeArea()

                VStack(spacing: 12) {
                    Text(recognizedItems.isEmpty ? "Point at text or a barcode" : "Tap to use a highlighted result")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .animation(.easeInOut(duration: 0.2), value: recognizedItems.isEmpty)

                    Button("Cancel") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 28)
                        .background(Color.black.opacity(0.5), in: Capsule())
                }
                .padding(.bottom, 36)
            }
            .preferredColorScheme(.dark)
        } else {
            NavigationStack {
                ContentUnavailableView(
                    "Scanner Not Available",
                    systemImage: "camera.fill",
                    description: Text("This device does not support live scanning, or camera access has been denied.")
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
    }
}
