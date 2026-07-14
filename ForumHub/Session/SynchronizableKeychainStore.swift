import Foundation
import Security

protocol KeychainDataAccessing {
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus
    func add(attributes: [String: Any]) -> OSStatus
    func loadData(query: [String: Any]) -> (OSStatus, Data?)
    func delete(query: [String: Any]) -> OSStatus
}

struct SystemKeychainDataAccess: KeychainDataAccessing {
    func update(query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func add(attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func loadData(query: [String: Any]) -> (OSStatus, Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func delete(query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

enum SynchronizableKeychainError: LocalizedError, Equatable {
    case operationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .operationFailed(status):
            let detail = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "iCloud Keychain 操作失败：\(detail)"
        }
    }
}

struct SynchronizableKeychainStore {
    let service: String
    let account: String
    var access: any KeychainDataAccessing = SystemKeychainDataAccess()

    func save(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let updateStatus = access.update(query: baseQuery, attributes: attributes)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw SynchronizableKeychainError.operationFailed(updateStatus)
        }

        var addAttributes = baseQuery
        attributes.forEach { addAttributes[$0.key] = $0.value }
        let addStatus = access.add(attributes: addAttributes)
        guard addStatus == errSecSuccess else {
            throw SynchronizableKeychainError.operationFailed(addStatus)
        }
    }

    func load() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = access.loadData(query: query)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw SynchronizableKeychainError.operationFailed(status)
        }
        return data
    }

    func delete() throws {
        let status = access.delete(query: baseQuery)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SynchronizableKeychainError.operationFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true
        ]
    }
}
