import SwiftUI

/// Сотрудник → QR машины → подтверждение → машина привязана и настраивается
/// сама. Ключей нет: Spark присылает машине номер и настройки напрямую.
struct PairFlowView: View {
    let request: PairRequest

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .scanning

    enum Step {
        case scanning
        case loading
        case confirm(PairSource, PairPreview)
        case claiming(PairSource, PairPreview)
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
            if let source = request.source { await load(source) }
        }
    }

    private var title: String {
        switch step {
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
        case .scanning:
            ScannerView { code in Task { await load(.qr(code)) } }
        case .loading:
            ProgressView("Проверяю код…").frame(maxHeight: .infinity)
        case .confirm(let source, let preview):
            confirmView(source: source, preview: preview, busy: false)
        case .claiming(let source, let preview):
            confirmView(source: source, preview: preview, busy: true)
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

    private func confirmView(source: PairSource, preview: PairPreview, busy: Bool) -> some View {
        let wp = request.workplace
        return VStack(spacing: 20) {
            Spacer()
            HStack(spacing: 18) {
                Image(systemName: "person.fill")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                    .font(.title2)
                Image(systemName: "desktopcomputer")
            }
            .font(.system(size: 44))
            .foregroundStyle(.tint)

            Text("Привязать машину?").font(.title3.bold())

            VStack(spacing: 0) {
                row("Машина", preview.deviceName.isEmpty ? "без имени" : preview.deviceName)
                Divider()
                row("Код на экране", preview.code)
                Divider()
                if !preview.appVersion.isEmpty {
                    row("EliteSIP", preview.appVersion)
                    Divider()
                }
                row("Сотрудник", wp.fullName.isEmpty ? wp.label : wp.fullName)
                Divider()
                row("Добавочный", wp.extension_)
                Divider()
                row("Предустановка", wp.presetName.isEmpty ? "не выбрана" : wp.presetName)
            }
            .background(.fill.tertiary, in: .rect(cornerRadius: 14))
            .padding(.horizontal)

            Text("Сверьте код с экраном машины. После привязки она сама получит номер, SIP-пароль и настройки.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
            Button {
                Task { await claim(source: source, preview: preview) }
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
        let machine = result.machine
        return ContentUnavailableView {
            Label("Машина привязана", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        } description: {
            Text("«\(machine.deviceName.isEmpty ? "Машина" : machine.deviceName)» получит настройки \(machine.workplaceLabel) и поднимется сама — вводить на ней ничего не нужно.")
        }
    }

    private func load(_ source: PairSource) async {
        step = .loading
        do {
            let preview: PairPreview
            switch source {
            case .qr(let code): preview = try await model.client.previewPair(code)
            case .number(let number): preview = try await model.client.previewPairNumber(number)
            }
            switch preview.state {
            case "waiting": step = .confirm(source, preview)
            case "expired": step = .failed("Код устарел — на машине появится новый, отсканируйте его.")
            default: step = .failed("Эта машина уже привязана.")
            }
        } catch SparkError.unauthorized {
            model.handle(SparkError.unauthorized)
            dismiss()
        } catch {
            step = .failed(error.localizedDescription)
        }
    }

    private func claim(source: PairSource, preview: PairPreview) async {
        step = .claiming(source, preview)
        do {
            let result: PairClaimResult
            switch source {
            case .qr(let code):
                result = try await model.client.claimPair(code, workplaceID: request.workplace.id)
            case .number(let number):
                result = try await model.client.bindPairNumber(number, workplaceID: request.workplace.id)
            }
            if model.waitingMachine?.source == source { model.waitingMachine = nil }
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
