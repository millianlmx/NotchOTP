import Foundation
import Security

/// Stores the optional OATH applet password in the login keychain.
///
/// The biometry-protected variant of the keychain (`SecAccessControl` with
/// `kSecAttrAccessControl`) needs the data-protection keychain, which rejects
/// unsigned or ad-hoc signed apps with `errSecMissingEntitlement` (-34018).
/// This app therefore keeps the item in the login keychain and gates every read
/// behind a fresh `LAContext` evaluation in ``BiometricGate``.
public struct OATHPasswordStore: Sendable {

    public enum StoreError: Error, Equatable {
        case keychain(status: OSStatus, message: String)
    }

    private let service: String
    private let account: String

    public init(service: String = "app.yubiconotch.oath", account: String = "oath-password") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func password() throws(StoreError) -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status: status, message: Self.message(for: status))
        }
    }

    public func setPassword(_ password: String) throws(StoreError) {
        let data = Data(password.utf8)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)

        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw .keychain(status: addStatus, message: Self.message(for: addStatus))
            }
        default:
            throw .keychain(status: status, message: Self.message(for: status))
        }
    }

    public func removePassword() throws(StoreError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw .keychain(status: status, message: Self.message(for: status))
        }
    }

    private static func message(for status: OSStatus) -> String {
        (SecCopyErrorMessageString(status, nil) as String?) ?? "Code \(status)"
    }
}
