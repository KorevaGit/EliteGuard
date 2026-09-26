import SwiftUI

/// Сотрудника ещё нет в EliteSIP: заводим рабочее место, дальше — привязка
/// машины.
struct CreateWorkplaceView: View {
    let user: BitrixUser
    let created: (Workplace) -> Void

    @Environment(AppModel.self) private var model
    @State private var label = ""
    @State private var sipPassword = ""
    @State private var remote = false
    @State private var presetID: Int?
    @State private var presets: [Preset] = []
    @State private var busy = false

    var body: some View {
        Form {
            Section("Сотрудник") {
                LabeledContent("Имя", value: user.fullName)
                LabeledContent("Добавочный", value: user.callNumber.isEmpty ? "не указан в Битриксе" : user.callNumber)
            }
            if user.callNumber.isEmpty {
                Section {
                    Label("Без CALL_NUMBER в Битриксе машине не с чем работать", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TextField("Подпись профиля", text: $label, prompt: Text(user.lastName))
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
            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if busy { ProgressView() } else { Text("Создать рабочее место").bold() }
                        Spacer()
                    }
                }
                .disabled(busy || sipPassword.isEmpty || presetID == nil)
            }
        }
        .navigationTitle("Новое рабочее место")
        .navigationBarTitleDisplayMode(.inline)
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
            let wp = try await model.client.createWorkplace(WorkplaceInput(
                bitrixUserId: user.userId,
                label: label.isEmpty ? user.lastName : label,
                sipPassword: sipPassword,
                workFormat: remote ? "remote" : "office",
                presetId: presetID))
            created(wp)
        } catch {
            model.handle(error)
        }
    }
}
