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
    let pendingKeys: Int
    let lastSeenAt: Date?
    let appVersion: String

    var fullName: String { [lastName, firstName].filter { !$0.isEmpty }.joined(separator: " ") }

    enum CodingKeys: String, CodingKey {
        case id, bitrixUserId, firstName, lastName, label, workFormat, presetId, presetName
        case machines, pendingKeys, lastSeenAt, appVersion
        case extension_ = "extension"
    }
}

struct Activation: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let kind: String
    let keyPrefix: String
    let installationId: String
    let extension_: String
    let label: String
    let presetName: String
    let issuedByName: String
    let issuedAt: Date
    let expiresAt: Date
    let state: String
    let checkin: Checkin?

    enum CodingKeys: String, CodingKey {
        case id, kind, keyPrefix, installationId, label, presetName, issuedByName
        case issuedAt, expiresAt, state, checkin
        case extension_ = "extension"
    }

    var stateTitle: String {
        switch state {
        case "pending": "Ждёт машину"
        case "active": "Работает"
        case "expired": "Истёк"
        case "revoked": "Отозван"
        case "superseded": "Заменён"
        case "reflashed": "Перепрошит"
        default: state
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
    let activations: [Activation]
    let conflicts: [String]?
}

struct Preset: Decodable, Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
    let publishedRevision: Int
    let archivedAt: Date?
}

struct IssuedKey: Decodable, Sendable, Hashable {
    let key: String
    let activation: Activation
    let warning: String?
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
    let state: String
    let deviceName: String
    let appVersion: String
    let expiresAt: Date
}

struct PairClaimResult: Decodable, Sendable {
    let deviceName: String
    let activation: Activation
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
