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
            .searchable(text: $query, prompt: "Фамилия, имя или добавочный")
            .task(id: query) { await search() }
            .task { await loadWorkplaces() }
            .refreshable { await loadWorkplaces() }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .workplace(let id):
                    WorkplaceView(id: id)
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
                        }
                        .accessibilityLabel("Ручной профиль")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Сканировать", systemImage: "qrcode.viewfinder") { scanning = true }
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
        }
    }

    private func open(_ user: BitrixUser) {
        if let id = user.workplaceId {
            path.append(Route.workplace(id))
        } else {
            path.append(Route.create(user))
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
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(workplace.fullName.isEmpty ? workplace.label : workplace.fullName)
                Spacer()
                Text(workplace.extension_).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label("\(workplace.machines)", systemImage: "desktopcomputer")
                if workplace.lagging > 0 {
                    Label("\(workplace.lagging)", systemImage: "arrow.triangle.2.circlepath")
                }
                Text(workplace.presetName).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
