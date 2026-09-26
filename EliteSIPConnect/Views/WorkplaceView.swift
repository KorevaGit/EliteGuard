import SwiftUI

struct WorkplaceView: View {
    let id: Int
    let deleted: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var detail: WorkplaceDetail?
    @State private var revoking: Machine?
    @State private var editing = false
    @State private var pushing = false
    @State private var deleting = false
    @State private var confirmDelete = false

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

                Section {
                    Button("Изменить сотрудника", systemImage: "square.and.pencil") { editing = true }
                    if detail.machines.contains(where: { $0.state != "revoked" }) {
                        Button("Отправить настройки заново", systemImage: "paperplane") {
                            Task { await push() }
                        }
                        .disabled(pushing)
                    }
                }

                Section {
                    Button("Удалить пользователя", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                    .disabled(deleting || detail.machines.contains { $0.state != "revoked" })
                } footer: {
                    if detail.machines.contains(where: { $0.state != "revoked" }) {
                        Text("Перед удалением отвяжите все машины пользователя.")
                    }
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
                        VStack(alignment: .leading, spacing: 8) {
                            MachineRow(machine: machine)
                            if machine.state != "revoked" {
                                Button("Отвязать машину", systemImage: "link.badge.minus", role: .destructive) {
                                    revoking = machine
                                }
                                .font(.subheadline)
                                .buttonStyle(.borderless)
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
        .sheet(isPresented: $editing) {
            if let detail {
                NavigationStack {
                    EditWorkplaceView(workplace: detail.workplace) { result in
                        editing = false
                        Task { await load() }
                        model.alert = result.warning ??
                            (result.pushed > 0 ? "Сохранено и отправлено на \(result.pushed) машин" : "Сохранено")
                    }
                }
            }
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
        .confirmationDialog("Удалить пользователя из EliteSIP?", isPresented: $confirmDelete) {
            Button("Удалить пользователя", role: .destructive) { Task { await remove() } }
        } message: {
            Text("Профиль и его настройки будут удалены. Пользователь Битрикса останется в Битриксе.")
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

    private func remove() async {
        deleting = true
        defer { deleting = false }
        do {
            try await model.client.deleteWorkplace(id)
            deleted()
            dismiss()
        } catch {
            model.handle(error)
        }
    }

    private func push() async {
        pushing = true
        defer { pushing = false }
        do {
            let result = try await model.client.pushWorkplace(id)
            model.alert = result.warning ?? "Настройки отправлены на \(result.pushed) машин"
            await load()
        } catch {
            model.handle(error)
        }
    }
}

struct EditWorkplaceView: View {
    let workplace: Workplace
    let saved: (WorkplaceUpdateResult) -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var firstName: String
    @State private var lastName: String
    @State private var extensionNumber: String
    @State private var label: String
    @State private var sipPassword: String
    @State private var remote: Bool
    @State private var presetID: Int?
    @State private var presets: [Preset] = []
    @State private var lines: [WorkplaceLineDraft]
    @State private var busy = false

    init(workplace: Workplace, saved: @escaping (WorkplaceUpdateResult) -> Void) {
        self.workplace = workplace
        self.saved = saved
        _firstName = State(initialValue: workplace.firstName)
        _lastName = State(initialValue: workplace.lastName)
        _extensionNumber = State(initialValue: workplace.extension_)
        _label = State(initialValue: workplace.label)
        _sipPassword = State(initialValue: workplace.sipPassword ?? "")
        _remote = State(initialValue: workplace.workFormat == "remote")
        _presetID = State(initialValue: workplace.presetId)
        _lines = State(initialValue: (workplace.lines ?? []).map(WorkplaceLineDraft.init))
    }

    var body: some View {
        Form {
            if workplace.bitrixUserId == 0 {
                Section("Имя Фамилия") {
                    TextField("Имя", text: $firstName)
                    TextField("Фамилия", text: $lastName)
                }
            } else {
                Section {
                    LabeledContent("Имя", value: workplace.fullName)
                    LabeledContent("Добавочный", value: workplace.extension_)
                } header: {
                    Text("Сотрудник из Битрикса")
                } footer: {
                    Text("Имя и номер берутся из Битрикса.")
                }
            }
            Section("Настройки") {
                if workplace.bitrixUserId == 0 {
                    TextField("Номер", text: $extensionNumber).keyboardType(.numberPad)
                }
                TextField("Подпись профиля", text: $label)
                SecureField("SIP-пароль", text: $sipPassword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Формат", selection: $remote) {
                    Text("Офис").tag(false)
                    Text("Удалёнка").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Предустановка", selection: $presetID) {
                    Text("Не выбрана").tag(Int?.none)
                    ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if workplace.bitrixUserId == 0 {
                Section("Дополнительные номера") {
                    ForEach($lines) { $line in
                        VStack(alignment: .leading) {
                            TextField("Добавочный", text: $line.extensionNumber).keyboardType(.numberPad)
                            TextField("Подпись", text: $line.label)
                            SecureField("SIP-пароль", text: $line.sipPassword)
                        }
                    }
                    .onDelete { lines.remove(atOffsets: $0) }
                    if lines.count < 8 {
                        Button("Добавить номер", systemImage: "plus") {
                            lines.append(WorkplaceLineDraft())
                        }
                    }
                }
            }
        }
        .navigationTitle("Изменить сотрудника")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lastName) { oldValue, newValue in
            if label.isEmpty || label == oldValue { label = newValue }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Отмена") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }
                    .disabled(busy || sipPassword.isEmpty || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                              (workplace.bitrixUserId == 0 &&
                               ((firstName.isEmpty && lastName.isEmpty) || extensionNumber.isEmpty ||
                                lines.contains { $0.extensionNumber.isEmpty || $0.sipPassword.isEmpty })))
            }
        }
        .task {
            do { presets = try await model.client.presets() }
            catch { model.handle(error) }
        }
    }

    private func save() async {
        busy = true
        defer { busy = false }
        do {
            var input = WorkplaceInput(
                bitrixUserId: workplace.bitrixUserId,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                sipPassword: sipPassword,
                workFormat: remote ? "remote" : "office",
                presetId: presetID)
            input.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.extension_ = extensionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            input.note = workplace.note ?? ""
            input.lines = lines.map(\.input)
            saved(try await model.client.updateWorkplace(workplace.id, input: input))
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
