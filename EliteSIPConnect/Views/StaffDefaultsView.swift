import SwiftUI

struct StaffDefaultsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var defaults = StaffDefaults(presetId: nil, sipPassword: "")
    @State private var presets: [Preset] = []
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Новые сотрудники") {
                Picker("Предустановка", selection: $defaults.presetId) {
                    Text("Не выбрана").tag(Int?.none)
                    ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                }
                Text("Стандартный SIP-пароль берётся отдельно для каждого номера из FreePBX.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle("Стандартные настройки")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Сохранить") { Task { await save() } }.disabled(saving)
            }
        }
        .task {
            do {
                async let loadedDefaults = model.client.staffDefaults()
                async let loadedPresets = model.client.presets()
                defaults = try await loadedDefaults
                presets = try await loadedPresets
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            defaults.sipPassword = ""
            _ = try await model.client.saveStaffDefaults(defaults)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
