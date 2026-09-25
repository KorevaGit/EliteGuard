import SwiftUI

struct WorkplaceView: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var detail: WorkplaceDetail?
    @State private var issuing = false
    @State private var confirmIssue = false
    @State private var note = ""

    var body: some View {
        List {
            if let detail {
                let wp = detail.workplace
                Section {
                    LabeledContent("Добавочный", value: wp.extension_)
                    LabeledContent("Подпись", value: wp.label)
                    LabeledContent("Формат", value: wp.workFormat == "remote" ? "Удалёнка" : "Офис")
                    LabeledContent("Предустановка", value: wp.presetName.isEmpty ? "не выбрана" : wp.presetName)
                }

                if let conflicts = detail.conflicts, !conflicts.isEmpty {
                    Section {
                        Label("На этом добавочном уже работают: \(conflicts.joined(separator: ", "))",
                              systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        confirmIssue = true
                    } label: {
                        HStack {
                            Label(model.waitingMachine == nil ? "Выпустить ключ" : "Выпустить и привязать",
                                  systemImage: "key.fill")
                                .bold()
                            Spacer()
                            if issuing { ProgressView() }
                        }
                    }
                    .disabled(issuing || wp.presetId == nil)
                } footer: {
                    if let machine = model.waitingMachine {
                        Text("Ключ сразу уйдёт на «\(machine.preview.deviceName)».")
                    } else {
                        Text("Ключ живёт 48 часов. После выпуска отсканируйте QR на машине.")
                    }
                }

                Section("Ключи и машины") {
                    if detail.activations.isEmpty {
                        Text("Ключей ещё не выпускали").foregroundStyle(.secondary)
                    }
                    ForEach(detail.activations) { ActivationRow(activation: $0) }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(detail?.workplace.fullName ?? "Рабочее место")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .onChange(of: model.pairRequest == nil) { _, closed in
            if closed { Task { await load() } }
        }
        .alert("Выпустить ключ?", isPresented: $confirmIssue) {
            TextField("Заметка (необязательно)", text: $note)
            Button("Выпустить") { Task { await issue() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Ключ показывается один раз. Невостребованные ключи сверх трёх вытесняются.")
        }
    }

    private func load() async {
        do {
            detail = try await model.client.workplace(id)
        } catch {
            model.handle(error)
        }
    }

    private func issue() async {
        issuing = true
        defer { issuing = false }
        do {
            let issued = try await model.client.issueKey(workplaceID: id, note: note)
            note = ""
            model.keyIssued(issued)
            await load()
        } catch {
            model.handle(error)
        }
    }
}

struct ActivationRow: View {
    let activation: Activation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(activation.keyPrefix + "-••••-••••").font(.body.monospaced())
                Spacer()
                Text(activation.stateTitle)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.15), in: .capsule)
                    .foregroundStyle(color)
            }
            HStack {
                Text(activation.kind == "reflash" ? "перепрошивка" : "активация")
                Text("·")
                Text(activation.issuedAt, format: .dateTime.day().month().hour().minute())
                if !activation.issuedByName.isEmpty { Text("· \(activation.issuedByName)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let checkin = activation.checkin {
                Text("На связи \(checkin.lastSeenAt, format: .relative(presentation: .named)) · \(checkin.appVersion)")
                    .font(.caption)
                    .foregroundStyle(checkin.silent ? .orange : .secondary)
            }
        }
    }

    private var color: Color {
        switch activation.state {
        case "active": .green
        case "pending": .blue
        case "revoked", "expired": .red
        default: .gray
        }
    }
}
