import Foundation

// Модели ответов Spark. Поля — как в JSON бэкенда, змеиный регистр
// переводится декодером.

struct LoginResponse: Decodable, Sendable {
    let accessToken: String
    let accessExpiresAt: Date?
    let userId: String?
    let name: String?
}

struct ItemsResponse<T: Decodable & Sendable>: Decodable, Sendable {
    let items: [T]
}

struct BitrixUser: Decodable, Identifiable, Hashable, Sendable {
    let userId: Int
    let firstName: String
    let lastName: String
    let callNumber: String
    let dateOfDismissal: String?
    let workplaceId: Int?

    var id: Int { userId }
    var fullName: String { [lastName, firstName].filter { !$0.isEmpty }.joined(separator: " ") }
    var isDismissed: Bool { !(dateOfDismissal ?? "").isEmpty }
}

struct Workplace: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let bitrixUserId: Int
    let firstName: String
    let lastName: String
    let extension_: String
    let label: String
    let workFormat: String
    let presetId: Int?
    let presetName: String
    let machines: Int
    let lagging: Int
    let lastSeenAt: Date?
    let appVersion: String

    var fullName: String { [lastName, firstName].filter { !$0.isEmpty }.joined(separator: " ") }

    enum CodingKeys: String, CodingKey {
        case id, bitrixUserId, firstName, lastName, label, workFormat, presetId, presetName
        case machines, lagging, lastSeenAt, appVersion
        case extension_ = "extension"
    }
}

/// Машина, привязанная к сотруднику. Ключей больше нет: машину привязывают
/// по QR или коду с её экрана, и Spark сам присылает ей настройки.
struct Machine: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let installationId: String
    let deviceName: String
    let workplaceLabel: String
    let state: String
    let configRevision: Int
    let applied: Bool
    let boundAt: Date
    let boundByName: String
    let revokedAt: Date?
    let checkin: Checkin?

    var stateTitle: String {
        switch state {
        case "revoked": "Отвязана"
        case "legacy": "Ждёт обновления"
        default:
            if checkin == nil { "Не выходила на связь" } else if !applied { "Применяет настройки" } else { "Работает" }
        }
    }
}

struct Checkin: Decodable, Hashable, Sendable {
    let lastSeenAt: Date
    let appVersion: String
    let silent: Bool
}

struct WorkplaceDetail: Decodable, Sendable {
    let workplace: Workplace
    let machines: [Machine]
    let conflicts: [String]?
}

struct Preset: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let publishedRevision: Int
    let archivedAt: Date?
}

struct WorkplaceInput: Encodable, Sendable {
    var bitrixUserId: Int
    var label: String
    var sipPassword: String
    var workFormat: String
    var presetId: Int?
    var note: String = ""
}

struct PairPreview: Decodable, Sendable {
    let sessionId: String
    let code: String
    let state: String
    let deviceName: String
    let appVersion: String
    let expiresAt: Date
}

struct PairClaimResult: Decodable, Sendable {
    let machine: Machine
}

/// Содержимое QR с экрана клиента: `elitesip://pair?s=<сессия>&f=<отпечаток>`.
struct PairCode: Hashable, Sendable {
    let session: String
    let fingerprint: String

    init?(_ raw: String) {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "elitesip", url.host() == "pair",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let s = items.first(where: { $0.name == "s" })?.value,
              let f = items.first(where: { $0.name == "f" })?.value,
              s.count == 32, f.count == 16,
              s.allSatisfy(\.isHexDigit), f.allSatisfy(\.isHexDigit)
        else { return nil }
        session = s.lowercased()
        fingerprint = f.lowercased()
    }
}
