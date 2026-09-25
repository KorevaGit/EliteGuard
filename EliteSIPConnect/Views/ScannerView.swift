import SwiftUI
import VisionKit

/// Сканер QR клиента EliteSIP. Там, где камеры нет (симулятор), — поле для
/// вставки ссылки из QR.
struct ScannerView: View {
    let found: (PairCode) -> Void

    @State private var manual = ""
    @State private var rejected = false

    var body: some View {
        if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
            ZStack(alignment: .bottom) {
                QRScanner { payload in
                    if let code = PairCode(payload) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        found(code)
                        return true
                    }
                    rejected = true
                    return false
                }
                .ignoresSafeArea()

                Text(rejected ? "Это не QR клиента EliteSIP" : "Наведите камеру на QR-код в окне EliteSIP")
                    .font(.callout)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .glassEffect()
                    .padding(.bottom, 40)
            }
        } else {
            Form {
                Section {
                    TextField("elitesip://pair?s=…&f=…", text: $manual, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.callout.monospaced())
                } header: {
                    Text("Камера недоступна")
                } footer: {
                    Text("Вставьте ссылку из QR-кода клиента EliteSIP.")
                }
                Button("Продолжить") {
                    if let code = PairCode(manual) { found(code) } else { rejected = true }
                }
                .disabled(manual.isEmpty)
                if rejected {
                    Text("Ссылка не похожа на QR клиента EliteSIP").foregroundStyle(.red)
                }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    /// Возвращает true, если код принят и сканирование пора остановить.
    let onPayload: (String) -> Bool

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ vc: DataScannerViewController, coordinator: Coordinator) {
        vc.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onPayload: onPayload) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onPayload: (String) -> Bool
        private var done = false

        init(onPayload: @escaping (String) -> Bool) { self.onPayload = onPayload }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue, onPayload(payload) {
                    done = true
                    scanner.stopScanning()
                    return
                }
            }
        }
    }
}
