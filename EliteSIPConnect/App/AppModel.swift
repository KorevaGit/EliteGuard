import SwiftUI

/// Машина, отсканированная раньше, чем выбран сотрудник: её код ждёт, пока
/// установщик его выберет.
struct WaitingMachine: Hashable {
    let code: PairCode
    let preview: PairPreview

    static func == (a: Self, b: Self) -> Bool { a.code == b.code }
    func hash(into h: inout Hasher) { h.combine(code) }
}

/// Что сейчас привязываем: к какому сотруднику и, если уже известна, какую
/// машину.
struct PairRequest: Identifiable {
    let id = UUID()
    let workplace: Workplace
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
                    ? "Код устарел — на машине появится новый"
                    : "Эта машина уже привязана"
                return
            }
            waitingMachine = WaitingMachine(code: code, preview: preview)
        } catch {
            handle(error)
        }
    }

    /// Привязать машину к сотруднику: если машина уже ждёт, сразу к
    /// подтверждению, иначе — к сканеру.
    func bind(to workplace: Workplace) {
        pairRequest = PairRequest(workplace: workplace, code: waitingMachine?.code)
    }

    func open(url: URL) {
        guard let code = PairCode(url.absoluteString) else { return }
        Task { await machineScanned(code) }
    }
}
