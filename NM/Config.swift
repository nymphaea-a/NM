import Foundation

// MARK: - 数据模型

protocol AIConfigProtocol {
    var apiKey: String { get }
    var baseURL: String { get }
    var model: String { get }
}

struct ParticipantConfig: Codable, AIConfigProtocol {
    var name: String
    var apiKey: String
    var baseURL: String
    var model: String
    
    // Keychain Account 命名
    var apiKeyAccount: String { "participant.\(name).apiKey" }
    var baseURLAccount: String { "participant.\(name).baseURL" }
    
    // 从 Keychain 加载敏感信息
    static func loadFromKeychain(name: String, model: String) -> ParticipantConfig {
        let apiKeyAccount = "participant.\(name).apiKey"
        let baseURLAccount = "participant.\(name).baseURL"
        
        let apiKey = (try? KeychainService.loadSecret(account: apiKeyAccount)) ?? ""
        let baseURL = (try? KeychainService.loadSecret(account: baseURLAccount)) ?? ""
        
        return ParticipantConfig(name: name, apiKey: apiKey, baseURL: baseURL, model: model)
    }
    
    // 保存到 Keychain
    func saveToKeychain() {
        try? KeychainService.saveSecret(account: apiKeyAccount, secret: apiKey)
        try? KeychainService.saveSecret(account: baseURLAccount, secret: baseURL)
    }
    
    // 从 Keychain 删除
    func deleteFromKeychain() {
        try? KeychainService.deleteSecret(account: apiKeyAccount)
        try? KeychainService.deleteSecret(account: baseURLAccount)
    }
}

struct SecretaryConfig: Codable, AIConfigProtocol {
    var apiKey: String
    var baseURL: String
    var model: String
    
    // Keychain Account 命名
    static let apiKeyAccount = "secretary.apiKey"
    static let baseURLAccount = "secretary.baseURL"
    
    // 从 Keychain 加载敏感信息
    static func loadFromKeychain(model: String) -> SecretaryConfig {
        let apiKey = (try? KeychainService.loadSecret(account: apiKeyAccount)) ?? ""
        let baseURL = (try? KeychainService.loadSecret(account: baseURLAccount)) ?? ""
        
        return SecretaryConfig(apiKey: apiKey, baseURL: baseURL, model: model)
    }
    
    // 保存到 Keychain
    func saveToKeychain() {
        try? KeychainService.saveSecret(account: Self.apiKeyAccount, secret: apiKey)
        try? KeychainService.saveSecret(account: Self.baseURLAccount, secret: baseURL)
    }
    
    // 从 Keychain 删除
    static func deleteFromKeychain() {
        try? KeychainService.deleteSecret(account: apiKeyAccount)
        try? KeychainService.deleteSecret(account: baseURLAccount)
    }
}

// MARK: - Config.json 存储的结构（仅非敏感信息）

struct AppConfig: Codable {
    var userName: String
    var secretaryModel: String
    var participantNames: [String]
    var participantModels: [String]
    var customStorageBookmark: Data?
    
    // 转换为完整配置（合并 Keychain 数据）
    func toFullConfig() -> FullConfig {
        let secretary = SecretaryConfig.loadFromKeychain(model: secretaryModel)
        var participants: [ParticipantConfig] = []
        
        for i in 0..<participantNames.count {
            let name = participantNames[i]
            let model = i < participantModels.count ? participantModels[i] : ""
            participants.append(ParticipantConfig.loadFromKeychain(name: name, model: model))
        }
        
        return FullConfig(userName: userName, secretary: secretary, participants: participants, customStorageBookmark: customStorageBookmark)
    }
}

// MARK: - 完整配置（运行时使用）

struct FullConfig {
    var userName: String
    var secretary: SecretaryConfig
    var participants: [ParticipantConfig]
    var customStorageBookmark: Data?
}

// MARK: - Config 单例

struct Config {
    private(set) static var shared: FullConfig = loadConfig()

    static func reload() {
        shared = loadConfig()
    }
    
    // 保存配置（分离存储）
    static func save(appConfig: AppConfig) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL.appendingPathComponent("Config.json")
        
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(appConfig)
            try data.write(to: configURL)
        } catch {
            print("⚠️ Config.json 保存失败：\(error.localizedDescription)")
        }
    }

    private static func loadConfig() -> FullConfig {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL.appendingPathComponent("Config.json")

        // 如果 Documents 中已存在配置文件，加载并合并 Keychain 数据
        if fileManager.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let decoder = JSONDecoder()
                let appConfig = try decoder.decode(AppConfig.self, from: data)
                return appConfig.toFullConfig()
            } catch {
                fatalError("Config.json 解析失败: \(error.localizedDescription)")
            }
        }

        // 否则从 Bundle 复制默认模板到 Documents
        guard let bundleURL = Bundle.main.url(forResource: "Config", withExtension: "json") else {
            fatalError("Config.json 未找到，请确保该文件已添加到 Xcode 项目且位于 Copy Bundle Resources 中。")
        }
        do {
            try fileManager.copyItem(at: bundleURL, to: configURL)
            let data = try Data(contentsOf: configURL)
            let decoder = JSONDecoder()
            let appConfig = try decoder.decode(AppConfig.self, from: data)
            return appConfig.toFullConfig()
        } catch {
            fatalError("无法复制 Config.json 到 Documents: \(error.localizedDescription)")
        }
    }
}
