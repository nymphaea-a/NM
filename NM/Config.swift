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
}

struct SecretaryConfig: Codable, AIConfigProtocol {
    var apiKey: String
    var baseURL: String
    var model: String
}

struct AppConfig: Codable {
    var userName: String
    var meetingName: String
    var secretary: SecretaryConfig
    var participants: [ParticipantConfig]
}

// MARK: - Config 单例

struct Config {
    private(set) static var shared: AppConfig = loadConfig()

    static func reload() {
        shared = loadConfig()
    }

    /// Sanitize meeting name: remove characters that could cause issues in
    /// window titles or file names. Keeps only CJK, letters, digits, spaces,
    /// commas, periods, underscores, and hyphens.
    static func sanitizeMeetingName(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-., ")
            .union(CharacterSet.cjkUnifiedIdeographs)
        let sc = raw.unicodeScalars.filter { allowed.contains($0) }
        return String(String.UnicodeScalarView(sc)).trimmingCharacters(in: .whitespaces)
    }

    private static func loadConfig() -> AppConfig {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL.appendingPathComponent("Config.json")

        // 如果 Documents 中已存在配置文件，直接加载
        if fileManager.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                let decoder = JSONDecoder()
                return try decoder.decode(AppConfig.self, from: data)
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
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            fatalError("无法复制 Config.json 到 Documents: \(error.localizedDescription)")
        }
    }
}

extension CharacterSet {
    static let cjkUnifiedIdeographs = CharacterSet(charactersIn:
        "\u{4E00}"..."\u{9FFF}"
    )
}
