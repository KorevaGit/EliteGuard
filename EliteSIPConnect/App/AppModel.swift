import SwiftUI

/// Машина, отсканированная раньше, чем выпущен ключ: её код ждёт, пока
/// установщик выберет сотрудника.
struct WaitingMachine: Hashable {
    let code: PairCode
    let preview: PairPreview

    static func == (a: Self, b: Self) -> Bool { a.code == b.code }
    func hash(into h: inout Hasher) { h.combine(code) }
}

/// Что сейчас привязываем: ключ и, если уже известна, машина.
struct PairRequest: Identifiable {
    let id = UUID()
    let issued: IssuedKey
    var code: PairCode?
}

@MainActor @Observable
final class AppModel {
    let client = SparkClient.shared

    var signedIn = false
    var userName = ""
    var waitingMachine: WaitingMachine?
    var pairRequest: PairRequest?
    var alert: String?

    init() {
        Task { signedIn = await client.isSignedIn }
        userName = UserDefaults.standard.string(forKey: "user_name") ?? ""
    }

    func signIn(login: String, password: String, local: Bool) async throws {
        let response = try await client.login(login: login, password: password, local: local)
        userName = response.name ?? login
        UserDefaults.standard.set(userName, forKey: "user_name")
        signedIn = true
    }

    func signOut() async {
        await client.logout()
        signedIn = false
        waitingMachine = nil
        pairRequest = nil
    }

    /// Любая ошибка API: истёкшая сессия возвращает на вход.
    func handle(_ error: Error) {
        if case SparkError.unauthorized = error {
            signedIn = false
            return
        }
        alert = error.localizedDescription
    }

    /// Код пришёл ссылкой (системная камера) или со сканера главного экрана.
    func machineScanned(_ code: PairCode) async {
        do {
            let preview = try await client.previewPair(code)
            guard preview.state == "waiting" else {
                alert = preview.state == "expired"
                    ? "Код устарел — обновите QR на машине"
                    : "К этой машине уже привязан ключ"
                return
            }
            waitingMachine = WaitingMachine(code: code, preview: preview)
        } catch {
            handle(error)
        }
    }

    /// Ключ выпущен: если машина уже ждёт, сразу к подтверждению.
    func keyIssued(_ issued: IssuedKey) {
        pairRequest = PairRequest(issued: issued, code: waitingMachine?.code)
    }

    func open(url: URL) {
        guard let code = PairCode(url.absoluteString) else { return }
        Task { await machineScanned(code) }
    }
}
