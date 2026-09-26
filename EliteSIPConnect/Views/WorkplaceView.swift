import SwiftUI

struct WorkplaceView: View {
    let id: Int
    @Environment(AppModel.self) private var model
    @State private var detail: WorkplaceDetail?
    @State private var revoking: Machine?

    var body: some View {
        List {
            if let detail {
                let wp = detail.workplace
                Section {
                    LabeledContent("Добавочный", value: wp.extension_)
                    LabeledContent("Подпись", value: wp.label)
                    LabeledContent("Формат", value: wp.workFormat == "remote" ? "Удалёнка" : "Офис")
                    LabeledContent("Предустановка", value: wp.presetName.isEmpty ? "не выбрана" : wp.presetName)
                } footer: {
                    Text("Правки в Spark уезжают на машины сотрудника сами — в течение 15 минут.")
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
                        model.bind(to: wp)
                    } label: {
                        Label(model.waitingMachine == nil ? "Привязать машину" : "Привязать ждущую машину",
                              systemImage: "qrcode.viewfinder")
                            .bold()
                    }
                    .disabled(wp.presetId == nil)
                } footer: {
                    if let machine = model.waitingMachine {
                        Text("К сотруднику привяжется «\(machine.preview.deviceName)» (код \(machine.preview.code)).")
                    } else {
                        Text("Отсканируйте QR на экране EliteSIP — машина получит номер и настройки сама.")
                    }
                }

                Section("Машины") {
                    if detail.machines.isEmpty {
                        Text("Машин пока нет").foregroundStyle(.secondary)
                    }
                    ForEach(detail.machines) { machine in
                        MachineRow(machine: machine)
                            .swipeActions {
                                if machine.state != "revoked" {
                                    Button("Отвязать", role: .destructive) { revoking = machine }
                                }
                            }
                    }
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
        .confirmationDialog(
            "Отвязать машину?",
            isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }),
            titleVisibility: .visible,
            presenting: revoking
        ) { machine in
            Button("Отвязать", role: .destructive) { Task { await revoke(machine) } }
        } message: { machine in
            Text("«\(machine.deviceName.isEmpty ? "Машина" : machine.deviceName)» сбросится при следующей проверке — в течение 15 минут.")
        }
    }

    private func load() async {
        do {
            detail = try await model.client.workplace(id)
        } catch {
            model.handle(error)
        }
    }

    private func revoke(_ machine: Machine) async {
        do {
            try await model.client.revokeMachine(machine.id)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            await load()
        } catch {
            model.handle(error)
        }
    }
}

struct MachineRow: View {
    let machine: Machine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(machine.deviceName.isEmpty ? "Машина" : machine.deviceName)
                Spacer()
                Text(machine.stateTitle)
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color.opacity(0.15), in: .capsule)
                    .foregroundStyle(color)
            }
            HStack {
                Text(String(machine.installationId.prefix(8))).monospaced()
                Text("·")
                Text(machine.boundAt, format: .dateTime.day().month().hour().minute())
                if !machine.boundByName.isEmpty { Text("· \(machine.boundByName)") }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let checkin = machine.checkin {
                Text("На связи \(checkin.lastSeenAt, format: .relative(presentation: .named)) · \(checkin.appVersion)")
                    .font(.caption)
                    .foregroundStyle(checkin.silent ? .orange : .secondary)
            }
        }
        .opacity(machine.state == "revoked" ? 0.55 : 1)
    }

    private var color: Color {
        switch machine.state {
        case "revoked": .gray
        case "legacy": .orange
        default: machine.checkin != nil && machine.applied ? .green : .blue
        }
    }
}
