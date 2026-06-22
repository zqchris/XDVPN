import Foundation
import Security

enum KeychainPersistentReferenceStore {
    static func savePassword(_ password: String, account: String) throws -> Data {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { throw KeychainStoreError.emptyAccount }

        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: SharedConstants.keychainService,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(baseQuery as CFDictionary)

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = Data(password.utf8)
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        addQuery[kSecReturnPersistentRef as String] = true

        var result: CFTypeRef?
        let status = SecItemAdd(addQuery as CFDictionary, &result)
        guard status == errSecSuccess, let persistentRef = result as? Data else {
            throw KeychainStoreError.security(status)
        }

        return persistentRef
    }
}

enum KeychainStoreError: LocalizedError {
    case emptyAccount
    case security(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyAccount:
            return "用户名和服务器不能为空"
        case .security(let status):
            return "Keychain 写入失败（OSStatus \(status)）"
        }
    }
}
