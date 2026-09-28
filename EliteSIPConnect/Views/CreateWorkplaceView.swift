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
    @State private var useStandardPassword = true
    @State private var standardAvailable = false
    @State private var remote = false
    @State private var presetID: Int?
    @State private var presets: [Preset] = []
    @State private var lines: [WorkplaceLineDraft] = []
    @State private var busy = false

    var body: some View {
        Form {
            if let user {
                Section("Сотрудник из Битрикса") {
                    GlassGroup {
                        GlassRow { LabeledContent("Имя", value: user.fullName) }
                        GlassDivider()
                        GlassRow { LabeledContent("Добавочный", value: user.callNumber.isEmpty ? "не указан" : user.callNumber) }
                    }
                }
                if user.callNumber.isEmpty {
                    Section {
                        GlassGroup {
                            GlassRow {
                                Label("Без номера из Битрикса машина не сможет работать", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } else {
                Section("Имя Фамилия") {
                    GlassGroup {
                        GlassRow { TextField("Имя", text: $firstName) }
                        GlassDivider()
                        GlassRow { TextField("Фамилия", text: $lastName) }
                    }
                }
            }

            Section("Настройки") {
                GlassGroup {
                    if user == nil {
                        GlassRow { TextField("Номер", text: $extensionNumber).keyboardType(.numberPad) }
                        GlassDivider()
                    }
                    GlassRow { TextField("Подпись", text: $label) }
                    GlassDivider()
                    GlassRow {
                        Picker("SIP-пароль", selection: $useStandardPassword) {
                            Text("Стандартный · FreePBX").tag(true)
                            Text("Ручной").tag(false)
                        }
                        .disabled(!standardAvailable)
                    }
                    if !useStandardPassword {
                        GlassDivider()
                        GlassRow {
                            SecureField("SIP-пароль", text: $sipPassword)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                    }
                    GlassDivider()
                    GlassRow {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Формат").font(.subheadline).foregroundStyle(.secondary)
                            Picker("Формат", selection: $remote) {
                                Text("Офис").tag(false)
                                Text("Удалёнка").tag(true)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }
                    }
                    GlassDivider()
                    GlassRow {
                        Picker("Предустановка", selection: $presetID) {
                            Text("Не выбрана").tag(Int?.none)
                            ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                }
            }

            if user == nil {
                Section("Дополнительные номера") {
                    GlassGroup {
                        ForEach($lines) { $line in
                            GlassRow {
                                VStack(alignment: .leading, spacing: 10) {
                                    TextField("Добавочный", text: $line.extensionNumber).keyboardType(.numberPad)
                                    TextField("Подпись", text: $line.label)
                                    SecureField("SIP-пароль", text: $line.sipPassword)
                                    Button("Удалить номер", systemImage: "trash", role: .destructive) {
                                        lines.removeAll { $0.id == line.id }
                                    }
                                }
                            }
                            GlassDivider()
                        }
                        if lines.count < 8 {
                            GlassRow {
                                Button("Добавить номер", systemImage: "plus") {
                                    lines.append(WorkplaceLineDraft())
                                }
                            }
                        }
                    }
                }
            }

            Section {
                GlassGroup {
                    GlassRow {
                        Button {
                            Task { await create() }
                        } label: {
                            HStack {
                                Spacer()
                                if busy { ProgressView() } else { Text("Создать профиль").bold() }
                                Spacer()
                            }
                        }
                        .disabled(busy || (useStandardPassword && !standardAvailable) || (!useStandardPassword && sipPassword.isEmpty) || label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                  (user == nil && ((firstName.isEmpty && lastName.isEmpty) ||
                                                   extensionNumber.isEmpty || !extensionNumber.allSatisfy(\.isNumber) ||
                                                   lines.contains { $0.extensionNumber.isEmpty || $0.sipPassword.isEmpty })))
                    }
                }
            }
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
                async let loadedPresets = model.client.presets()
                async let loadedDefaults = model.client.staffDefaults()
                presets = try await loadedPresets
                let defaults = try await loadedDefaults
                standardAvailable = defaults.standardPasswordSource == "freepbx"
                useStandardPassword = standardAvailable
                presetID = defaults.presetId
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
                sipPassword: useStandardPassword ? "" : sipPassword,
                workFormat: remote ? "remote" : "office",
                presetId: presetID)
            input.firstName = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.sipPasswordSource = useStandardPassword ? "standard" : "manual"
            input.lastName = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            input.extension_ = extensionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            input.lines = lines.map(\.input)
            created(try await model.client.createWorkplace(input))
        } catch {
            model.handle(error)
        }
    }
}
