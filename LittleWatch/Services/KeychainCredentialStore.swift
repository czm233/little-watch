import Foundation
import Security

enum CredentialStoreError: LocalizedError, Sendable {
    case invalidData
    case keychain(OSStatus)

    var errorDescription: String? {
        switch self {
        case .invalidData:
            "Keychain 中的密码数据无效"
        case let .keychain(status):
            "Keychain 操作失败（\(status)）"
        }
    }
}

final class KeychainCredentialStore: @unchecked Sendable {
    private let service: String
    private let account: String

    init(
        service: String = "com.littlewatch.source.cpa-usage-keeper",
        account: String = "administrator-password"
    ) {
        self.service = service
        self.account = account
    }

    func savePassword(_ password: String) throws {
        let data = Data(password.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }

        var item = baseQuery
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.keychain(addStatus)
        }
    }

    func loadPassword() throws -> String? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw CredentialStoreError.keychain(status)
        }
        guard
            let data = result as? Data,
            let password = String(data: data, encoding: .utf8)
        else {
            throw CredentialStoreError.invalidData
        }
        return password
    }

    func deletePassword() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    func containsPassword() throws -> Bool {
        try loadPassword() != nil
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}
