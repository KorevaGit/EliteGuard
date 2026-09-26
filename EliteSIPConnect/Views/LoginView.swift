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
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 32)

                    VStack(spacing: 18) {
                        ZStack {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 124, weight: .ultraLight))
                                .foregroundStyle(.tint)
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .systemGroupedBackground))
                                .frame(width: 66, height: 66)
                            Image("Crown")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 52, height: 52)
                                .accessibilityHidden(true)
                        }
                        .frame(height: 150)
                        .accessibilityLabel("EliteGuard")

                        VStack(spacing: 7) {
                            Text("EliteGuard")
                                .font(.system(size: 34, weight: .bold, design: .rounded))
                            Text("Подключение сотрудников и машин EliteSIP")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    Spacer(minLength: 68)

                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Способ входа")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Picker("Способ входа", selection: $local) {
                                Text("Битрикс").tag(false)
                                Text("Spark").tag(true)
                            }
                            .pickerStyle(.segmented)
                            Text(local
                                 ? "Учётная запись Spark — отдельный логин и пароль, выданные администратором. Используйте её, если вам не назначен вход через Битрикс."
                                 : "Войдите с логином и паролем Битрикс. Нужен доступ к разделу EliteSIP в Spark.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
                            .frame(height: 58)

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
                            .frame(height: 58)
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
                    .padding(.bottom, 22)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemGroupedBackground))
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
