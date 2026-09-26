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
        VStack(spacing: 0) {
            ZStack {
                Image("LoginQR")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 136, height: 136)
                    .mask { Rectangle().padding(12) }
                QRCornerMarks()
                    .stroke(.tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .frame(width: 154, height: 154)
            }
                .frame(width: 154, height: 154)
                .accessibilityLabel("EliteGuard")
                .padding(.top, 20)

            Text("EliteGuard")
                .font(.system(size: 29, weight: .bold, design: .rounded))
                .padding(.top, 4)

            VStack(spacing: 12) {
                Picker("Способ входа", selection: $local) {
                    Text("Битрикс").tag(false)
                    Text("Spark").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 6)

                TextField(local ? "Логин Spark" : "Логин Битрикс", text: $login)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .login)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .modifier(LoginFieldStyle())

                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .modifier(LoginFieldStyle())

                Button(action: submit) {
                    Group {
                        if busy { ProgressView().tint(.white) }
                        else { Text("Войти").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .foregroundStyle(.white)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(busy || login.isEmpty || password.isEmpty)
                .opacity(busy || login.isEmpty || password.isEmpty ? 0.55 : 1)
                .padding(.top, 4)

                if focus == nil {
                    Text(local
                         ? "Spark: отдельный логин и пароль, выданные администратором."
                         : "Вход через Битрикс. Нужен доступ к EliteSIP в Spark.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 460)
            .padding(.top, 36)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
        .background(Color(uiColor: .systemGroupedBackground))
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

private struct QRCornerMarks: Shape {
    func path(in rect: CGRect) -> Path {
        let length: CGFloat = 24
        let radius: CGFloat = 14
        let inset: CGFloat = 5
        var path = Path()
        path.move(to: CGPoint(x: inset, y: length + inset))
        path.addLine(to: CGPoint(x: inset, y: radius + inset))
        path.addQuadCurve(to: CGPoint(x: radius + inset, y: inset), control: CGPoint(x: inset, y: inset))
        path.addLine(to: CGPoint(x: length + inset, y: inset))
        path.move(to: CGPoint(x: rect.maxX - length - inset, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - radius - inset, y: inset))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: radius + inset), control: CGPoint(x: rect.maxX - inset, y: inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: length + inset))
        path.move(to: CGPoint(x: inset, y: rect.maxY - length - inset))
        path.addLine(to: CGPoint(x: inset, y: rect.maxY - radius - inset))
        path.addQuadCurve(to: CGPoint(x: radius + inset, y: rect.maxY - inset), control: CGPoint(x: inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: length + inset, y: rect.maxY - inset))
        path.move(to: CGPoint(x: rect.maxX - length - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - radius - inset, y: rect.maxY - inset))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - radius - inset), control: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.maxY - length - inset))
        return path
    }
}

private struct LoginFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .frame(height: 54)
            .glassEffect(.regular, in: .rect(cornerRadius: 13))
    }
}
