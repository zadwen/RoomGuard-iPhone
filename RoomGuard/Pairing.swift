import Foundation
import CryptoKit
import Security

struct Pairing: Codable, Equatable {
    let v: Int
    let url: String
    let key: String

    var keyData: Data {
        Data(base64Encoded: key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"))!
    }
    var token: String {
        HMAC<SHA256>.authenticationCode(for: Data("RoomGuard API v1".utf8), using: SymmetricKey(data: keyData))
            .map { String(format: "%02x", $0) }.joined()
    }
    var socketURL: URL {
        var parts = URLComponents(string: url)!
        parts.scheme = "wss"
        parts.path = "/v1/live"
        parts.query = "fps=30"
        return parts.url!
    }
    static func parse(_ text: String) throws -> Pairing {
        guard text.utf8.count < 4096, let bytes = text.data(using: .utf8),
              let value = try? JSONDecoder().decode(Pairing.self, from: bytes), value.v == 1,
              let parts = URLComponents(string: value.url), parts.scheme == "https",
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil, parts.port == nil || parts.port == 443,
              parts.path == "" || parts.path == "/", parts.url != nil,
              let key = Data(base64Encoded: value.key.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")),
              key.count == 32 else { throw ViewerError.invalidPairing }
        return value
    }
}

enum ViewerError: LocalizedError {
    case invalidPairing, invalidFrame, keychain
    var errorDescription: String? {
        switch self {
        case .invalidPairing: return "Use the QR code or pairing text from Phone viewing in RoomGuard on your PC."
        case .invalidFrame: return "The camera frame could not be verified. Pair with your PC again."
        case .keychain: return "iPhone could not save your pairing key. Unlock your phone and try again."
        }
    }
}

enum FrameDecoder {
    static func decode(_ packet: Data, key: Data) throws -> (timestamp: UInt64, jpeg: Data) {
        guard packet.count > 36, packet.count < 2_000_000 else { throw ViewerError.invalidFrame }
        let box = try AES.GCM.SealedBox(combined: packet)
        let plain = try AES.GCM.open(box, using: SymmetricKey(data: key), authenticating: Data("RoomGuard frame v1".utf8))
        guard plain.count > 8 else { throw ViewerError.invalidFrame }
        let timestamp = plain.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return (timestamp, Data(plain.dropFirst(8)))
    }
}

enum PairingStore {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "RoomGuard.Pairing", kSecAttrAccount as String: "camera"]
    }
    static func load() -> Pairing? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return try? Pairing.parse(text)
    }
    static func save(_ pairing: Pairing) throws {
        let data = try JSONEncoder().encode(pairing)
        let changes: [String: Any] = [kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            changes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw ViewerError.keychain }
        } else if result != errSecSuccess { throw ViewerError.keychain }
    }
    static func clear() { SecItemDelete(query as CFDictionary) }
}
