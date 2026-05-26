import Foundation
import Security

struct KeychainService {
    
    private static let serviceName = "com.noizelab.NM"
    
    // MARK: - 保存敏感信息
    
    static func saveSecret(account: String, secret: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecValueData as String: secret.data(using: .utf8)!,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        if status == errSecDuplicateItem {
            try updateSecret(account: account, secret: secret)
        } else if status != errSecSuccess {
            throw NSError(domain: "KeychainService", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain 保存失败"])
        }
    }
    
    // MARK: - 读取敏感信息
    
    static func loadSecret(account: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecItemNotFound {
            return nil
        } else if status != errSecSuccess {
            throw NSError(domain: "KeychainService", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain 读取失败"])
        }
        
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    
    // MARK: - 更新敏感信息
    
    private static func updateSecret(account: String, secret: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let attributes: [String: Any] = [
            kSecValueData as String: secret.data(using: .utf8)!
        ]
        
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        
        if status != errSecSuccess {
            throw NSError(domain: "KeychainService", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain 更新失败"])
        }
    }
    
    // MARK: - 删除敏感信息
    
    static func deleteSecret(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        if status != errSecSuccess && status != errSecItemNotFound {
            throw NSError(domain: "KeychainService", code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Keychain 删除失败"])
        }
    }
}
