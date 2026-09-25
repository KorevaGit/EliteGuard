import SwiftUI

/// Выпущенный ключ → QR машины → подтверждение → ключ на машине.
struct PairFlowView: View {
    let request: PairRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .key
    @State private var copied = false

    enum Step {
        case key
        case scanning
        case loading
        case confirm(PairCode, PairPreview)
        case claiming(PairCode, PairPreview)
        case done(PairClaimResult)
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        if case .done = step {
                            EmptyView()
                        } else {
                            Button("Закрыть") { dismiss() }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        if case .done = step { Button("Готово") { dismiss() }.bold() }
                    }
                }
        }
        .interactiveDismissDisabled(isBusy)
        .task {
            if let code = request.code { await load(code) }
        }
    }

    private var title: String {
        switch step {
        case .key: "Ключ выпущен"
        case .scanning: "QR-код машины"
        case .done: "Готово"
        default: "Привязка"
        }
    }

    private var isBusy: Bool {
        if case .claiming = step { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .key:
            keyView
        case .scanning:
            ScannerView { code in Task { await load(code) } }
        case .loading:
            ProgressView("Проверяю код…").frame(maxHeight: .infinity)
        case .confirm(let code, let preview):
            confirmView(code: code, preview: preview, busy: false)
        case .claiming(let code, let preview):
            confirmView(code: code, preview: preview, busy: true)
        case .done(let result):
            doneView(result)
        case .failed(let message):
            ContentUnavailableView {
                Label("Не получилось", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Сканировать снова") { step = .scanning }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var keyView: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 8) {
                Text(request.issued.activation.label.isEmpty ? "Ключ активации" : request.issued.activation.label)
                    .font(.headline)
                Text("доб. \(request.issued.activation.extension_) · \(request.issued.activation.presetName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(request.issued.key)
                .font(.system(size: 34, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity)
                .background(.fill.tertiary, in: .rect(cornerRadius: 16))
                .padding(.horizontal)

            if let warning = request.issued.warning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.orange).padding(.horizontal)
            }

            Text("Ключ показывается один раз и живёт 48 часов. Отсканируйте QR на экране EliteSIP — ключ уйдёт на машину сам.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            VStack(spacing: 12) {
                Button {
                    step = .scanning
                } label: {
                    Label("Привязать к машине", systemImage: "qrcode.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Button {
                    UIPasteboard.general.string = request.issued.key
                    copied = true
                } label: {
                    Label(copied ? "Скопировано" : "Скопировать ключ",
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func confirmView(code: PairCode, preview: PairPreview, busy: Bool) -> some View {
        let a = request.issued.activation
        return VStack(spacing: 20) {
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "key.fill")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                Image(systemName: "desktopcomputer")
            }
            .font(.system(size: 44))
            .foregroundStyle(.tint)

            Text("Привязать ключ к машине?").font(.title3.bold())

            VStack(spacing: 0) {
                row("Машина", preview.deviceName.isEmpty ? "без имени" : preview.deviceName)
                Divider()
                if !preview.appVersion.isEmpty {
                    row("EliteSIP", preview.appVersion)
                    Divider()
                }
                row("Сотрудник", a.label)
                Divider()
                row("Добавочный", a.extension_)
                Divider()
                row("Ключ", a.keyPrefix + "-…")
            }
            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
            .padding(.horizontal)

            HStack(spacing: 4) {
                Text("Код действует ещё")
                Text(preview.expiresAt, style: .timer).monospacedDigit()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)

            Spacer()
            Button {
                Task { await claim(code: code, preview: preview) }
            } label: {
                Group {
                    if busy { ProgressView() } else { Text("Привязать").bold() }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(busy)
            .padding(.horizontal)

            Button("Другая машина") { step = .scanning }
                .disabled(busy)
                .padding(.bottom)
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func doneView(_ result: PairClaimResult) -> some View {
        ContentUnavailableView {
            Label("Ключ отправлен", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } description: {
            Text("«\(result.deviceName.isEmpty ? "Машина" : result.deviceName)» получит ключ и активирует рабочее место \(result.activation.label) (доб. \(result.activation.extension_)).")
        }
    }

    private func load(_ code: PairCode) async {
        step = .loading
        do {
            let preview = try await model.client.previewPair(code)
            switch preview.state {
            case "waiting": step = .confirm(code, preview)
            case "expired": step = .failed("Код устарел — на машине появится новый, отсканируйте его.")
            default: step = .failed("К этой машине уже привязан ключ.")
            }
        } catch SparkError.unauthorized {
            model.handle(SparkError.unauthorized)
            dismiss()
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func claim(code: PairCode, preview: PairPreview) async {
        step = .claiming(code, preview)
        do {
            let result = try await model.client.claimPair(code, key: request.issued.key)
            if model.waitingMachine?.code == code { model.waitingMachine = nil }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            step = .done(result)
        } catch SparkError.unauthorized {
            model.handle(SparkError.unauthorized)
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            step = .failed(error.localizedDescription)
        }
    }
}
