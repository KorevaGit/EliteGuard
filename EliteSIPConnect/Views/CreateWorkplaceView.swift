import SwiftUI

/// Профиль из Битрикса открывается из поиска; кнопка в панели создаёт только
/// ручной профиль без связи с Битриксом.
struct CreateWorkplaceView: View {
    let user: BitrixUser?
    let created: (Workplace) -> Void

    @Environment(AppModel.self) private var model
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var extensionNumber = ""
    @State private var label = ""
    @State private var sipPassword = ""
    @State private var remote = false
    @State private var presetID: Int?
    @State private var presets: [Preset] = []
    @State private var lines: [WorkplaceLineDraft] = []
    @State private var busy = false

    var body: some View {
        Form {
            if let user {
                Section("Сотрудник из Битрикса") {
                    LabeledContent("Имя", value: user.fullName)
                    LabeledContent("Добавочный", value: user.callNumber.isEmpty ? "не указан" : user.callNumber)
                }
                .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))
                if user.callNumber.isEmpty {
                    Section {
                        Label("Без номера из Битрикса машина не сможет работать", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                    }
                    .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))
                }
            } else {
                Section("Имя Фамилия") {
                    TextField("Имя", text: $firstName)
                    TextField("Фамилия", text: $lastName)
                }
                .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))
            }

            Section("Настройки") {
                if user == nil {
                    TextField("Номер", text: $extensionNumber)
                        .keyboardType(.numberPad)
                }
                TextField("Подпись", text: $label)
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
            .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))

            if user == nil {
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
                .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text("Создать профиль").bold() }
                        Spacer()
                    }
                }
                .disabled(busy || sipPassword.isEmpty || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                          (user == nil && ((firstName.isEmpty && lastName.isEmpty) ||
                                           extensionNumber.isEmpty || !extensionNumber.allSatisfy(\.isNumber) ||
                                           lines.contains { $0.extensionNumber.isEmpty || $0.sipPassword.isEmpty })))
            }
            .listRowBackground(Color.clear.glassEffect(.regular, in: .rect(cornerRadius: 14)))
        }
        .navigationTitle(user == nil ? "Ручной профиль" : "Новый сотрудник")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let user, label.isEmpty { label = user.lastName }
        }
        .onChange(of: lastName) { oldValue, newValue in
            if label.isEmpty || label == oldValue { label = newValue }
        }
        .task {
            do {
                presets = try await model.client.presets()
                if presets.count == 1 { presetID = presets[0].id }
            } catch {
                model.handle(error)
            }
        }
    }

    private func create() async {
        busy = true
        defer { busy = false }
        do {
            var input = WorkplaceInput(
                bitrixUserId: user?.userId ?? 0,
                label: label.trimmingCharacters(in: .whitespacesAndNewlines),
                sipPassword: sipPassword,
                workFormat: remote ? "remote" : "office",
                presetId: presetID)
            input.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.extension_ = extensionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lines = lines.map(\.input)
            created(try await model.client.createWorkplace(input))
        } catch {
            model.handle(error)
        }
    }
}
