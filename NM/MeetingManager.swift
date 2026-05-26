import Foundation

// MARK: - URL 安全书签扩展（适配Mac App Sandbox）
extension URL {
    func securityBookmark() throws -> Data {
        return try self.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    
    static func from(securityBookmark: Data) throws -> (URL, Bool) {
        var isStale = false
        let url = try URL(resolvingBookmarkData: securityBookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        return (url, isStale)
    }
}

struct MeetingSession {
    let topic: String
    let startTime: Date
    let dirURL: URL
    let dirBookmark: Data
}

struct MeetingManager {
    static func getRagBaseDir() throws -> (url: URL, hasAccess: Bool) {
        guard let bookmark = Config.shared.customStorageBookmark else {
            throw NSError(domain: "NMError", code: -1, userInfo: [NSLocalizedDescriptionKey: "存储路径未设置，请先在设置中配置NM存储位置"])
        }
        
        do {
            // 从安全书签还原URL
            let (baseURL, isStale) = try URL.from(securityBookmark: bookmark)
            
            // 书签过期，需要用户重新授权
            if isStale {
                throw NSError(domain: "NMError", code: -2, userInfo: [NSLocalizedDescriptionKey: "存储路径权限已过期，请重新在设置中选择存储位置"])
            }
            
            // 获取安全访问权限，交由上层调用方负责释放
            let hasAccess = baseURL.startAccessingSecurityScopedResource()
            guard hasAccess else {
                throw NSError(domain: "NMError", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法获取目录访问权限，请重新在设置中选择存储位置"])
            }
            
            // 确保目录存在
            try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
            
            // 验证写入权限
            let testFileURL = baseURL.appendingPathComponent(".nm_write_test_\(UUID().uuidString)")
            try "test".write(to: testFileURL, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFileURL)
            
            // 统一使用NM存档总目录，避免用户根目录杂乱
            let archiveRootURL = baseURL.appendingPathComponent("NM存档", isDirectory: true)
            try FileManager.default.createDirectory(at: archiveRootURL, withIntermediateDirectories: true, attributes: nil)
            
            return (url: archiveRootURL, hasAccess: hasAccess)
        } catch {
            if let nmError = error as NSError? , nmError.domain == "NMError" {
                throw nmError
            }
            throw NSError(domain: "NMError", code: -4, userInfo: [NSLocalizedDescriptionKey: "存储路径已失效：\(error.localizedDescription)，请重新在设置中选择存储位置"])
        }
    }

    static func createMeeting(topic: String) throws -> MeetingSession {
        let fm = FileManager.default
        let sanitized = topic
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        
        // 获取存储根目录和权限持有状态
        let (archiveRootURL, hasAccess) = try getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMError", code: -3, userInfo: [NSLocalizedDescriptionKey: "无法获取目录访问权限，请重新在设置中选择存储位置"])
        }
        defer {
            // 所有目录创建完成后释放权限
            archiveRootURL.stopAccessingSecurityScopedResource()
        }
        
        let meetingDir = archiveRootURL.appendingPathComponent(sanitized)
        let uploadsDir = meetingDir.appendingPathComponent("uploads")
        let roundsDir = meetingDir.appendingPathComponent("rounds")

        try fm.createDirectory(at: uploadsDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: roundsDir, withIntermediateDirectories: true)

        let bookmark = try meetingDir.securityBookmark()
        return MeetingSession(topic: topic, startTime: Date(), dirURL: meetingDir, dirBookmark: bookmark)
    }

    static func roundFilePath(meetingDir: URL, round: Int) -> URL {
        meetingDir.appendingPathComponent("rounds/round-\(round).md")
    }

    static func archivePath(meetingDir: URL, topic: String) -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyyMMdd-HHmmss"
        let ts = df.string(from: Date())
        let safe = topic
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces)
        return meetingDir.appendingPathComponent("\(safe)_完整会议纪要_\(ts).md")
    }
}
