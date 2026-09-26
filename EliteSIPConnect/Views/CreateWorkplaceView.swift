import SwiftUI

/// Сотрудника ещё нет в EliteSIP: заводим рабочее место, дальше — привязка
/// машины.
struct CreateWorkplaceView: View {
    let user: BitrixUser?
    let created: (Workplace) -> Void

    @Environment(AppModel.self) private var model
    @State private var label = ""
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var extensionNumber = ""
    @State private var pickedUser: BitrixUser?
    @State private var manual = false
    @State private var query = ""
    @State private var results: [BitrixUser] = []
    @State private var lines: [WorkplaceLineDraft] = []
    @State private var sipPassword = ""
    @State private var remote = false
    @State private var presetID: Int?
    @State private var presets: [Preset] = []
    @State private var busy = false

    private var activeUser: BitrixUser? { pickedUser ?? user }

    var body: some View {
        Form {
            if let user = activeUser {
                Section("Сотрудник") {
                    LabeledContent("Имя", value: user.fullName)
                    LabeledContent("Добавочный", value: user.callNumber.isEmpty ? "не указан в Битриксе" : user.callNumber)
                    if self.user == nil {
                        Button("Выбрать другого") { pickedUser = nil }
                    }
                }
            } else if manual {
                Section("Сотрудник без Битрикса") {
                    TextField("Фамилия", text: $lastName)
                    TextField("Имя", text: $firstName)
                    TextField("Добавочный", text: $extensionNumber)
                        .keyboardType(.numberPad)
                }
            } else {
                Section("Найти в Битриксе") {
                    TextField("Фамилия, имя или ID", text: $query)
                        .textInputAutocapitalization(.never)
                    ForEach(results) { found in
                        Button {
                            if let workplaceID = found.workplaceId {
                                model.alert = "Сотрудник уже добавлен (рабочее место №\(workplaceID))"
                            } else {
                                pickedUser = found
                            }
                        } label: {
                            HStack {
                                Text(found.fullName)
                                Spacer()
                                Text(found.callNumber).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button("Создать без Битрикса") { manual = true }
                }
            }
            if activeUser?.callNumber.isEmpty == true {
                Section {
                    Label("Без CALL_NUMBER в Битриксе машине не с чем работать", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            if activeUser != nil || manual {
                Section {
                    TextField("Подпись профиля", text: $label, prompt: Text(activeUser?.lastName ?? lastName))
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
                if manual {
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
                Section {
                    Button {
                        Task { await create() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Добавить сотрудника").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || sipPassword.isEmpty ||
                              (manual && ((firstName.isEmpty && lastName.isEmpty) ||
                                          extensionNumber.isEmpty || !extensionNumber.allSatisfy(\.isNumber) ||
                                          lines.contains { $0.extensionNumber.isEmpty || $0.sipPassword.isEmpty })))
                }
            }
        }
        .navigationTitle("Новый сотрудник")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                presets = try await model.client.presets()
                if presets.count == 1 { presetID = presets[0].id }
            } catch {
                model.handle(error)
            }
        }
        .task(id: query) {
            guard activeUser == nil, !manual else { return }
            let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value.count >= 2 else { results = []; return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do { results = try await model.client.searchUsers(value) }
            catch { model.handle(error) }
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            var input = WorkplaceInput(
                bitrixUserId: activeUser?.userId ?? 0,
                label: label.isEmpty ? (activeUser?.lastName ?? lastName) : label,
                sipPassword: sipPassword,
                workFormat: remote ? "remote" : "office",
                presetId: presetID)
            input.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.extension_ = extensionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lines = lines.map(\.input)
            let wp = try await model.client.createWorkplace(input)
            created(wp)
        } catch {
            model.handle(error)
        }
    }
}
