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
    private var editing: Bool { focus != nil }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: editing ? 8 : 16) {
                Image("LoginQR")
                    .resizable()
                    .scaledToFit()
                    .frame(width: editing ? 82 : 188, height: editing ? 82 : 188)
                    .clipShape(RoundedRectangle(cornerRadius: editing ? 14 : 26))
                    .shadow(color: .blue.opacity(0.12), radius: 18, y: 8)
                    .accessibilityLabel("EliteGuard")

                Text("EliteGuard")
                    .font(.system(size: editing ? 25 : 34, weight: .bold, design: .rounded))

                if !editing {
                    Text("Подключение сотрудников и машин EliteSIP")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, editing ? 8 : 28)

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Способ входа")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Picker("Способ входа", selection: $local) {
                        Text("Битрикс").tag(false)
                        Text("Spark").tag(true)
                    }
                    .pickerStyle(.segmented)
                    if !editing {
                        Text(local
                             ? "Учётная запись Spark — отдельный логин и пароль, выданные администратором. Используйте её, если вам не назначен вход через Битрикс."
                             : "Войдите с логином и паролем Битрикс. Нужен доступ к разделу EliteSIP в Spark.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "person")
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        TextField(local ? "Логин Spark" : "Логин Битрикс", text: $login)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .login)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)

                    Divider().padding(.leading, 50)

                    HStack(spacing: 12) {
                        Image(systemName: "lock")
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                        SecureField("Пароль", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    Group {
                        if busy { ProgressView().tint(.white) }
                        else { Text("Войти").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .foregroundStyle(.white)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
                .disabled(busy || login.isEmpty || password.isEmpty)
                .opacity(busy || login.isEmpty || password.isEmpty ? 0.55 : 1)
            }
            .frame(maxWidth: 460)
            .padding(.top, editing ? 16 : 32)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .background(Color(uiColor: .systemGroupedBackground))
        .animation(.easeOut(duration: 0.2), value: editing)
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
