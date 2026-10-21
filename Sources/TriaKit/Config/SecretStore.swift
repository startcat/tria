import Foundation
import os
import Security

public protocol SecretStore: Sendable {
    func apiKey(for provider: ProviderID) throws -> String?
    func setAPIKey(_ key: String, for provider: ProviderID) throws
    func deleteAPIKey(for provider: ProviderID) throws
}

public enum SecretStoreError: Error, Equatable, Sendable {
    case keychain(Int32)
}

/// Keys en el Llavero de macOS (spec §11). Nunca en ficheros ni en logs.
public struct KeychainSecretStore: SecretStore {
    public static let defaultService = "cat.start.tria"
    public let service: String

    public init(service: String = defaultService) { self.service = service }

    private func query(_ provider: ProviderID) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    public func apiKey(for provider: ProviderID) throws -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw SecretStoreError.keychain(status) }
        return String(decoding: data, as: UTF8.self)
    }

    public func setAPIKey(_ key: String, for provider: ProviderID) throws {
        try deleteAPIKey(for: provider)
        var attributes = query(provider)
        attributes[kSecValueData as String] = Data(key.utf8)
        attributes[kSecAttrLabel as String] = "Lyncat Tria (\(provider.rawValue))"
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    public func deleteAPIKey(for provider: ProviderID) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw SecretStoreError.keychain(status) }
    }
}

public final class InMemorySecretStore: SecretStore {
    private let keys: OSAllocatedUnfairLock<[ProviderID: String]>

    public init(_ keys: [ProviderID: String] = [:]) { self.keys = OSAllocatedUnfairLock(initialState: keys) }

    public func apiKey(for provider: ProviderID) throws -> String? { keys.withLock { $0[provider] } }
    public func setAPIKey(_ key: String, for provider: ProviderID) throws { keys.withLock { $0[provider] = key } }
    public func deleteAPIKey(for provider: ProviderID) throws { keys.withLock { $0[provider] = nil } }
}

public enum APIKeyResolver {
    /// La variable de entorno gana si no está vacía; si no, el Llavero.
    public static func resolve(_ provider: ProviderID, environment: [String: String],
                               store: any SecretStore) throws -> String? {
        if let value = environment[provider.environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            return value
        }
        return try store.apiKey(for: provider)
    }

    public static func masked(_ key: String) -> String {
        guard key.count > 8 else { return "••••" }
        return "\(key.prefix(6))…\(key.suffix(4))"
    }
}
