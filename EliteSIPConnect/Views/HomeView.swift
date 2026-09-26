import SwiftUI

enum Route: Hashable {
    case workplace(Int)
    case create(BitrixUser?)
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()
    @State private var query = ""
    @State private var users: [BitrixUser] = []
    @State private var workplaces: [Workplace] = []
    @State private var searching = false
    @State private var loading = false
    @State private var scanning = false
    @State private var enteringNumber = false
    @State private var machineNumber = ""
    @State private var checkingNumber = false
    @State private var numberError: String?

    private var normalizedNumber: String { machineNumber.filter(\.isNumber) }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let machine = model.waitingMachine {
                    Section {
                        WaitingMachineRow(machine: machine) { model.waitingMachine = nil }
                    }
                }

                if query.trimmingCharacters(in: .whitespaces).count >= 2 {
                    Section("Сотрудники Битрикса") {
                        if searching && users.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if users.isEmpty {
                            Text("Никого не нашли").foregroundStyle(.secondary)
                        }
                        ForEach(users) { user in
                            Button { open(user) } label: { UserRow(user: user) }
                                .tint(.primary)
                        }
                    }
                } else {
                    Section {
                        if loading && workplaces.isEmpty {
                            ProgressView().frame(maxWidth: .infinity)
                        }
                        ForEach(workplaces) { wp in
                            NavigationLink(value: Route.workplace(wp.id)) { WorkplaceRow(workplace: wp) }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 22, for: .scrollContent)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Фамилия, имя или номер", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button("Очистить", systemImage: "xmark.circle.fill") { query = "" }
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(.regularMaterial, in: .capsule)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .task(id: query) { await search() }
            .task { await loadWorkplaces() }
            .refreshable { await loadWorkplaces() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .workplace(let id):
                    WorkplaceView(id: id) { Task { await loadWorkplaces() } }
                case .create(let user):
                    CreateWorkplaceView(user: user) { created in
                        path.removeLast()
                        path.append(Route.workplace(created.id))
                        Task { await loadWorkplaces() }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 0) {
                        Menu {
                            Text(model.userName)
                            Button("Выйти", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                                Task { await model.signOut() }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle")
                                .frame(width: 32, height: 32)
                        }
                        Button {
                            path.append(Route.create(nil))
                        } label: {
                            Image(systemName: "person.badge.plus")
                                .frame(width: 32, height: 32)
                                .offset(y: 2)
                        }
                        .accessibilityLabel("Ручной профиль")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 0) {
                        Button("Ввести номер машины", systemImage: "number") { enteringNumber = true }
                            .labelStyle(.iconOnly)
                        Button("Сканировать", systemImage: "qrcode.viewfinder") { scanning = true }
                            .labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(isPresented: $scanning) {
                NavigationStack {
                    ScannerView { code in
                        scanning = false
                        Task { await model.machineScanned(code) }
                    }
                    .navigationTitle("QR-код машины")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Отмена") { scanning = false } }
                    }
                }
            }
            .sheet(isPresented: $enteringNumber) {
                NavigationStack {
                    Form {
                        Section {
                            TextField("123-456", text: $machineNumber)
                                .keyboardType(.numberPad)
                        } header: {
                            Text("Номер машины")
                        } footer: {
                            Text("Введите шесть цифр с экрана EliteSIP. После проверки выберите сотрудника для привязки.")
                        }
                        if let numberError {
                            Text(numberError).foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Номер машины")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Отмена") { enteringNumber = false }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Проверить") { Task { await checkMachineNumber() } }
                                .disabled(normalizedNumber.count != 6 || checkingNumber)
                        }
                    }
                }
            }
        }
    }

    private func open(_ user: BitrixUser) {
        if let id = user.workplaceId {
            path.append(Route.workplace(id))
        } else {
            path.append(Route.create(user))
        }
    }

    private func checkMachineNumber() async {
        checkingNumber = true
        defer { checkingNumber = false }
        do {
            try await model.machineEntered(normalizedNumber)
            machineNumber = ""
            numberError = nil
            enteringNumber = false
        } catch {
            numberError = error.localizedDescription
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { users = []; return }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        searching = true
        defer { searching = false }
        do {
            let found = try await model.client.searchUsers(q)
            if !Task.isCancelled { users = found }
        } catch is CancellationError {
        } catch {
            if !Task.isCancelled { model.handle(error) }
        }
    }

    private func loadWorkplaces() async {
        loading = true
        defer { loading = false }
        do {
            workplaces = try await model.client.workplaces()
                .sorted { $0.fullName.localizedCompare($1.fullName) == .orderedAscending }
        } catch {
            model.handle(error)
        }
    }
}

struct WaitingMachineRow: View {
    let machine: WaitingMachine
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.tint, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(machine.preview.deviceName.isEmpty ? "Машина ждёт привязки" : machine.preview.deviceName)
                    .font(.headline)
                Text("Код \(machine.preview.code) · выберите сотрудника — машина привяжется к нему")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Сбросить", systemImage: "xmark.circle.fill", action: dismiss)
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
        }
    }
}

struct UserRow: View {
    let user: BitrixUser

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(user.fullName.isEmpty ? "Без имени" : user.fullName)
                Text(user.callNumber.isEmpty ? "нет добавочного" : "доб. \(user.callNumber)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if user.isDismissed {
                Text("уволен").font(.caption).foregroundStyle(.red)
            } else if user.workplaceId != nil {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Text("новый").font(.caption).foregroundStyle(.tint)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

struct WorkplaceRow: View {
    let workplace: Workplace

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(workplace.fullName.isEmpty ? workplace.label : workplace.fullName)
                Spacer()
                Text(workplace.extension_).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(workplace.presetName.isEmpty ? "Без предустановки" : workplace.presetName)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Circle().fill(status.color).frame(width: 7, height: 7)
                Text(status.title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var status: (title: String, color: Color) {
        if workplace.machines == 0 { return ("Без машины", .gray) }
        if workplace.lagging > 0 { return ("Применяет настройки", .orange) }
        if let seen = workplace.lastSeenAt, Date().timeIntervalSince(seen) > 5 * 24 * 60 * 60 {
            return ("Молчит", .orange)
        }
        return ("Работает", .green)
    }
}
