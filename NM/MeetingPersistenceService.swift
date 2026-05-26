import Foundation

struct MeetingPersistenceService {
    
    // MARK: - 文件路径
    
    private static func meetingStatePath(meetingDir: URL) -> URL {
        meetingDir.appendingPathComponent("meeting_state.json")
    }
    
    private static func meetingConfigPath(meetingDir: URL) -> URL {
        meetingDir.appendingPathComponent("meeting_config.json")
    }
    
    private static func conversationPath(meetingDir: URL) -> URL {
        meetingDir.appendingPathComponent("conversation.md")
    }
    
    // MARK: - 保存会议状态
    
    static func saveMeetingState(_ state: MeetingState, meetingDir: URL) throws {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(state)
        try data.write(to: meetingStatePath(meetingDir: meetingDir))
    }
    
    // MARK: - 读取会议状态
    
    static func loadMeetingState(meetingDir: URL) throws -> MeetingState {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let data = try Data(contentsOf: meetingStatePath(meetingDir: meetingDir))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MeetingState.self, from: data)
    }
    
    // MARK: - 保存会议配置快照（脱敏）
    
    static func saveMeetingConfigSnapshot(_ config: MeetingConfigSnapshot, meetingDir: URL) throws {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(config)
        try data.write(to: meetingConfigPath(meetingDir: meetingDir))
    }
    
    // MARK: - 读取会议配置快照
    
    static func loadMeetingConfigSnapshot(meetingDir: URL) throws -> MeetingConfigSnapshot {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let data = try Data(contentsOf: meetingConfigPath(meetingDir: meetingDir))
        let decoder = JSONDecoder()
        return try decoder.decode(MeetingConfigSnapshot.self, from: data)
    }
    
    // MARK: - 追加保存对话（增量）
    
    static func appendConversation(_ content: String, meetingDir: URL) throws {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let path = conversationPath(meetingDir: meetingDir)
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: path.path) {
            let handle = try FileHandle(forWritingTo: path)
            handle.seekToEndOfFile()
            if let data = content.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try content.write(to: path, atomically: true, encoding: .utf8)
        }
    }
    
    // MARK: - 读取完整对话
    
    static func loadConversation(meetingDir: URL) throws -> String {
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMPersistenceError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录"])
        }
        defer {
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let path = conversationPath(meetingDir: meetingDir)
        let fileManager = FileManager.default
        
        guard fileManager.fileExists(atPath: path.path) else {
            return ""
        }
        
        return try String(contentsOf: path, encoding: .utf8)
    }
}
