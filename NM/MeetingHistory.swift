import Foundation

// MARK: - 脱敏的参会者配置快照（不保存API Key、URL等隐私）
struct ParticipantConfigSnapshot: Codable {
    let name: String
    let model: String
}

// MARK: - 脱敏的秘书配置快照
struct SecretaryConfigSnapshot: Codable {
    let model: String
}

// MARK: - 参会者状态快照（用于续会时恢复状态）
struct ParticipantStatusSnapshot: Codable {
    let name: String
    let status: String  // "away" | "present" | "thinking" | "speaking"
}

// MARK: - 会议配置快照（保存到会议目录，脱敏）
struct MeetingConfigSnapshot: Codable {
    let userName: String
    let participants: [ParticipantConfigSnapshot]
    let secretary: SecretaryConfigSnapshot
    let participantStatuses: [ParticipantStatusSnapshot]
}

// MARK: - 会议状态（用于续会时恢复）
struct MeetingState: Codable {
    let topic: String
    let startTime: Date
    let currentRound: Int
    let secretaryPhase: String  // "idle" | "collecting" | "summarizing" | "done"
    let lastSavedRound: Int
    let lastSavedMessageCount: Int
    let uploadedFiles: [UploadedFileInfo]
}

// MARK: - 历史会议元数据（用于列表展示）
struct MeetingHistoryInfo: Identifiable {
    let id = UUID()
    let topic: String
    let startTime: Date
    let lastModified: Date
    let totalRounds: Int
    let dirURL: URL
    let state: MeetingState
    let config: MeetingConfigSnapshot?
}
