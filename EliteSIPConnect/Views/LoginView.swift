import SwiftUI

struct LoginView: View {
    @Environment(AppModel.self) private var model
    @State private var login = ""
    @State private var password = ""
    @State private var local = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    private enum Field { case login, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 56, weight: .light))
                            .foregroundStyle(.tint)
                        Text("EliteGuard")
                            .font(.title2.bold())
                        Text("Элитный Сочи · выпуск ключей и привязка рабочих мест EliteSIP")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField("Логин Битрикс", text: $login)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .login)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Пароль", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    Text("Вход в spark.elitesochi.com. Нужен доступ к разделу EliteSIP.")
                }

                Section {
                    Toggle("Локальная учётная запись", isOn: $local)
                }

                if let error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
                }

                Section {
                    Button(action: submit) {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Войти").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || login.isEmpty || password.isEmpty)
                }
            }
        }
    }

    private func submit() {
        guard !login.isEmpty, !password.isEmpty, !busy else { return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await model.signIn(login: login, password: password, local: local)
                password = ""
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
