import Foundation
import Security

enum SparkError: LocalizedError {
    case unauthorized
    case server(status: Int, message: String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Сессия истекла — войдите снова"
        case .server(_, let message): message
        case .transport(let message): message
        }
    }
}

/// Клиент API Spark. Токен доступа хранится в Keychain, токен обновления —
/// в cookie `refresh_token`, как у веб-интерфейса.
actor SparkClient {
    let baseURL: URL
    private let session: URLSession
    private var accessToken: String?
    private var refreshTask: Task<RefreshResult, Never>?

    private enum RefreshResult {
        case success(String)
        case invalid
        case unavailable
    }

    static let shared = SparkClient()

    init(baseURL: URL? = nil) {
        let configured = Bundle.main.object(forInfoDictionaryKey: "SparkBaseURL") as? String
        self.baseURL = baseURL ?? URL(string: configured ?? "https://spark.elitesochi.com")!
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpShouldSetCookies = true
        config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config)
        accessToken = Keychain.read("access_token")
    }

    var isSignedIn: Bool { accessToken != nil }

    // MARK: - Вход

    func login(login: String, password: String, local: Bool) async throws -> LoginResponse {
        struct Body: Encodable { let login, password, method: String }
        let response: LoginResponse = try await send(
            "POST", "/api/auth/login",
            body: Body(login: login, password: password, method: local ? "local" : "bitrix"),
            authorized: false)
        setToken(response.accessToken)
        return response
    }

    func logout() async {
        _ = try? await sendRaw("POST", "/api/auth/logout", body: Optional<Int>.none, authorized: true, retry: false)
        setToken(nil)
        let authURL = baseURL.appending(path: "api/auth")
        HTTPCookieStorage.shared.cookies(for: authURL)?
            .filter { $0.name == "refresh_token" }
            .forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    private func refresh() async -> RefreshResult {
        if let refreshTask { return await refreshTask.value }
        let task = Task { await performRefresh() }
        refreshTask = task
        let result = await task.value
        if case .success(let token) = result { setToken(token) }
        refreshTask = nil
        return result
    }

    private func performRefresh() async -> RefreshResult {
        do {
            let (data, status) = try await sendRaw(
                "POST", "/api/auth/refresh", body: [String: String](), authorized: false, retry: false)
            if status == 401 || status == 403 { return .invalid }
            guard status == 200,
                  let response = try? Self.decoder.decode(LoginResponse.self, from: data)
            else { return .unavailable }
            return .success(response.accessToken)
        } catch {
            return .unavailable
        }
    }

    private func setToken(_ token: String?) {
        accessToken = token
        if let token { Keychain.write("access_token", token) } else { Keychain.delete("access_token") }
    }

    // MARK: - EliteSIP

    func searchUsers(_ query: String) async throws -> [BitrixUser] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let r: ItemsResponse<BitrixUser> = try await send("GET", "/api/elitesip/bitrix-users?q=\(q)")
        return r.items
    }

    func workplaces() async throws -> [Workplace] {
        let r: ItemsResponse<Workplace> = try await send("GET", "/api/elitesip/workplaces")
        return r.items
    }

    func workplace(_ id: Int) async throws -> WorkplaceDetail {
        try await send("GET", "/api/elitesip/workplaces/\(id)")
    }

    func presets() async throws -> [Preset] {
        let r: ItemsResponse<Preset> = try await send("GET", "/api/elitesip/presets")
        return r.items.filter { $0.archivedAt == nil && $0.publishedRevision > 0 }
    }

    func createWorkplace(_ input: WorkplaceInput) async throws -> Workplace {
        try await send("POST", "/api/elitesip/workplaces", body: input)
    }

    func updateWorkplace(_ id: Int, input: WorkplaceInput) async throws -> WorkplaceUpdateResult {
        try await send("PUT", "/api/elitesip/workplaces/\(id)", body: input)
    }

    func pushWorkplace(_ id: Int) async throws -> WorkplacePushResult {
        try await send("POST", "/api/elitesip/workplaces/\(id)/push", body: Optional<Int>.none)
    }

    func revokeMachine(_ machineID: Int) async throws {
        let (data, status) = try await sendRaw("POST", "/api/elitesip/machines/\(machineID)/revoke",
                                               body: Optional<Int>.none, authorized: true, retry: true)
        guard (200..<300).contains(status) else {
            if status == 401 { throw SparkError.unauthorized }
            throw SparkError.server(status: status, message: Self.message(from: data, status: status))
        }
    }

    func previewPair(_ code: PairCode) async throws -> PairPreview {
        try await send("GET", "/api/elitesip/pair/\(code.session)?f=\(code.fingerprint)")
    }

    /// Привязывает отсканированную машину к сотруднику: Spark выложит ей
    /// настройки, и она поднимется сама.
    func claimPair(_ code: PairCode, workplaceID: Int) async throws -> PairClaimResult {
        struct Body: Encodable { let fingerprint: String; let workplaceId: Int }
        return try await send("POST", "/api/elitesip/pair/\(code.session)/claim",
                              body: Body(fingerprint: code.fingerprint, workplaceId: workplaceID))
    }

    // MARK: - Транспорт

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            if let date = ISO8601DateFormatter().date(from: raw) { return date }
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: raw) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Дата \(raw)"))
        }
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private func send<T: Decodable>(_ method: String, _ path: String, authorized: Bool = true) async throws -> T {
        try await send(method, path, body: Optional<Int>.none, authorized: authorized)
    }

    private func send<T: Decodable, B: Encodable>(_ method: String, _ path: String, body: B?, authorized: Bool = true) async throws -> T {
        let (data, status) = try await sendRaw(method, path, body: body, authorized: authorized, retry: true)
        guard (200..<300).contains(status) else {
            if status == 401 { throw SparkError.unauthorized }
            throw SparkError.server(status: status, message: Self.message(from: data, status: status))
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw SparkError.transport("Не удалось разобрать ответ сервера: \(error.localizedDescription)")
        }
    }

    private func sendRaw<B: Encodable>(_ method: String, _ path: String, body: B?, authorized: Bool, retry: Bool) async throws -> (Data, Int) {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw SparkError.transport("Некорректный адрес") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try Self.encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let requestToken = authorized ? accessToken : nil
        if let requestToken {
            request.setValue("Bearer \(requestToken)", forHTTPHeaderField: "Authorization")
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw SparkError.transport("Нет связи со Spark: \(error.localizedDescription)")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, authorized, retry {
            if accessToken != nil, accessToken != requestToken {
                return try await sendRaw(method, path, body: body, authorized: authorized, retry: false)
            }
            switch await refresh() {
            case .success:
                return try await sendRaw(method, path, body: body, authorized: authorized, retry: false)
            case .invalid:
                if accessToken == requestToken { setToken(nil) }
            case .unavailable:
                throw SparkError.transport("Не удалось продлить сессию. Проверьте соединение и повторите попытку.")
            }
        }
        if status == 401, authorized, !retry, accessToken == requestToken {
            setToken(nil)
        }
        return (data, status)
    }

    private static func message(from data: Data, status: Int) -> String {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["detail", "error", "message"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
            }
        }
        return switch status {
        case 403: "Нет доступа к разделу EliteSIP"
        case 404: "Не найдено"
        case 429: "Слишком много попыток, повторите позже"
        default: "Ошибка сервера (\(status))"
        }
    }
}

enum Keychain {
    private static let service = "com.elite.EliteGuard"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ account: String, _ value: String) {
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
