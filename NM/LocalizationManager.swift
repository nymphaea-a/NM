import SwiftUI
import Combine

enum AppLanguage: String {
    case chinese
    case english
}

class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    @Published var language: AppLanguage = .chinese {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
        }
    }

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            language = lang
        }
    }

    func setLanguage(_ lang: AppLanguage) {
        language = lang
    }
}

// MARK: - 便捷访问

extension LocalizationManager {

    var isChinese: Bool { language == .chinese }

    // MARK: - App 入口

    var appWindowTitle: String {
        "Normal Meeting"
    }

    var settingsMenuTitle: String {
        isChinese ? "设置..." : "Settings..."
    }

    // MARK: - 设置界面

    var settingsTitle: String {
        isChinese ? "⚙ 设置" : "⚙ Settings"
    }

    var cancel: String {
        isChinese ? "取消" : "Cancel"
    }

    var confirm: String {
        isChinese ? "确定" : "Confirm"
    }

    var userInfo: String {
        isChinese ? "用户信息" : "User Info"
    }

    var yourName: String {
        isChinese ? "你的名字" : "Your Name"
    }

    var namePrompt: String {
        isChinese ? "例如：nomo" : "e.g. nomo"
    }

    var storageSettings: String {
        isChinese ? "存储设置" : "Storage Settings"
    }

    var storageDescription: String {
        isChinese ? "NM会议数据、上传文件、会议纪要都将保存在此目录下。" : "NM meeting data, uploaded files, and meeting minutes will be saved in this directory."
    }

    var storageNotSelected: String {
        isChinese ? "未选择存储路径" : "No storage path selected"
    }

    var selectStorage: String {
        isChinese ? "选择位置" : "Select Location"
    }

    var selectStorageTitle: String {
        isChinese ? "选择NM存储位置" : "Select NM Storage Location"
    }

    var selectButton: String {
        isChinese ? "选择" : "Select"
    }

    var meetingSecretary: String {
        isChinese ? "会议秘书" : "Secretary"
    }

    var secretaryDescription: String {
        isChinese ? "秘书为必填项，负责汇总各方论述并生成会议纪要。" : "The Secretary is required and responsible for summarizing discussions and generating meeting minutes."
    }

    var apiKey: String {
        isChinese ? "API Key" : "API Key"
    }

    var apiURL: String {
        isChinese ? "API URL" : "API URL"
    }

    var modelLabel: String {
        isChinese ? "模型" : "Model"
    }

    var modelPlaceholder: String {
        isChinese ? "例如：qwen3.5-plus" : "e.g. qwen3.5-plus"
    }

    func participantAILabel(_ index: Int) -> String {
        let labels = isChinese ? ["①", "②", "③"] : ["①", "②", "③"]
        let prefix = isChinese ? "参会 AI " : "Participant AI "
        return prefix + labels[index]
    }

    var participantName: String {
        isChinese ? "名称" : "Name"
    }

    var participantNamePlaceholder: String {
        isChinese ? "例如：小鲸鱼" : "e.g. Alex"
    }

    var participantModelPlaceholder: String {
        isChinese ? "例如：deepseek-v4-pro" : "e.g. deepseek-v4-pro"
    }

    var thinkingModelInfo: String {
        isChinese ? "ℹ️ 本会议室仅支持可开启思考模式的 AI 模型（OpenAI 兼容模式）参会。会议秘书使用非思考模式 AI。" : "ℹ️ This meeting room only supports AI models with thinking mode enabled (OpenAI-compatible). The Secretary uses a non-thinking mode AI."
    }

    var keychainSecurityInfo: String {
        isChinese ? "🔒 API 密钥安全存储在 macOS 钥匙串中，不会上传至任何服务器。" : "🔒 API keys are securely stored in the macOS Keychain and will not be uploaded to any server."
    }

    var languageLabel: String {
        isChinese ? "语言 / Language" : "Language / 语言"
    }

    // MARK: - 设置界面校验错误

    var errorNameRequired: String {
        isChinese ? "请填写你的名字" : "Please fill in your name"
    }

    var errorStorageRequired: String {
        isChinese ? "请选择NM存储路径" : "Please select NM storage path"
    }

    var errorStorageAccessDenied: String {
        isChinese ? "无法获取目录访问权限，请重新选择其他目录" : "Unable to access directory, please select another location"
    }

    var errorStorageExpired: String {
        isChinese ? "存储路径权限已过期，请重新选择存储位置" : "Storage path permission expired, please re-select storage location"
    }

    var errorStorageInvalid: String {
        isChinese ? "存储路径已失效，请重新选择存储位置" : "Storage path is invalid, please re-select storage location"
    }

    func errorStorageNoWritePermission(_ desc: String) -> String {
        isChinese ? "存储路径无效或无写入权限：\(desc)，请选择文档、桌面等您有权限的个人目录" : "Storage path is invalid or has no write permission: \(desc). Please select a directory you have access to, such as Documents or Desktop."
    }

    var errorSecretaryRequired: String {
        isChinese ? "会议秘书为必填项，请完整填写 API Key、API URL 和模型" : "Secretary is required. Please fill in API Key, API URL, and Model completely."
    }

    func errorParticipantIncomplete(_ idx: Int) -> String {
        let num = isChinese ? ["①", "②", "③"][idx] : ["①", "②", "③"][idx]
        return isChinese
            ? "参会 AI \(num) 的字段未填写完整（名称、API Key、API URL、模型均需填写）"
            : "Participant AI \(num) fields are incomplete (Name, API Key, API URL, and Model are all required)."
    }

    func errorStorageBookmarkAccessDenied(_ desc: String) -> String {
        isChinese
            ? "无法获取目录访问权限：\(desc)，请重新选择其他目录"
            : "Unable to access directory: \(desc). Please select another location."
    }

    func errorSaveFailed(_ desc: String) -> String {
        isChinese ? "保存失败：\(desc)" : "Save failed: \(desc)"
    }

    // MARK: - 新建会议界面

    var newMeetingTitle: String {
        isChinese ? "新建会议" : "New Meeting"
    }

    var startMeeting: String {
        isChinese ? "开始会议" : "Start Meeting"
    }

    var meetingTopic: String {
        isChinese ? "会议主题" : "Meeting Topic"
    }

    var topicPlaceholder: String {
        isChinese ? "请输入会议主题" : "Please enter a meeting topic"
    }

    var meetingTime: String {
        isChinese ? "会议时间" : "Meeting Time"
    }

    var uploadFiles: String {
        isChinese ? "上传文件" : "Upload Files"
    }

    var uploadSupportHint: String {
        isChinese ? "支持 txt / md / pdf 格式，上传后可供参会 AI 参考" : "Supports txt / md / pdf formats. Uploaded files can be referenced by participating AIs."
    }

    var noFiles: String {
        isChinese ? "暂无文件" : "No files"
    }

    var selectFiles: String {
        isChinese ? "选择文件" : "Select Files"
    }

    // MARK: - 历史会议界面

    var historyTitle: String {
        isChinese ? "历史会议" : "Meeting History"
    }

    var closeButton: String {
        isChinese ? "关闭" : "Close"
    }

    var noHistory: String {
        isChinese ? "暂无历史会议" : "No meeting history"
    }

    func roundLabel(_ round: Int) -> String {
        isChinese ? "第 \(round) 轮" : "Round \(round)"
    }

    var resumeButton: String {
        isChinese ? "续开" : "Resume"
    }

    // MARK: - 主界面

    var participantsSection: String {
        isChinese ? "参会人员" : "Participants"
    }

    var uploadedDocuments: String {
        isChinese ? "已上传文档" : "Uploaded Documents"
    }
    
    var clickDocumentToQuoteHint: String {
        isChinese ? "发言时可点击下方文档引用其完整文件名，大幅提升AI分析准确度" : "Click documents below to insert full filename, improves AI analysis accuracy"
    }
    
    // MARK: 悄悄问秘书相关
    var secretaryBusyTip: String {
        isChinese ? "秘书正在忙，请稍后再试" : "Secretary is busy, please try again later"
    }
    
    var whisperWindowTitle: String {
        isChinese ? "悄悄问秘书" : "Whisper to Secretary"
    }
    
    var whisperInputPlaceholder: String {
        isChinese ? "输入你的问题..." : "Enter your question..."
    }
    
    var whisperSystemPrompt: String {
        isChinese ? "你是会议秘书，也是用户的贴心小助手。请用温柔简洁的语气回答问题，回答控制在3-5句话，不超过150字。回答要直接有用，像朋友一样自然交流，不需要客套和开场白，但要把问题解释清楚。" : "You are the meeting secretary and the user's caring assistant. Answer questions in a warm, gentle tone in 3-5 sentences, no more than 150 words. Be direct and helpful like a friend chatting, no formal greetings, but ensure the answer fully explains the question."
    }
    
    var whisperErrorTip: String {
        isChinese ? "回答生成失败，请重试" : "Failed to generate answer, please try again"
    }

    var historyMeetingButton: String {
        isChinese ? "历史会议" : "History"
    }

    var newMeetingButton: String {
        isChinese ? "新建会议" : "New Meeting"
    }

    var endMeetingButton: String {
        isChinese ? "结束会议" : "End Meeting"
    }

    var settingsSidebarButton: String {
        isChinese ? "设置" : "Settings"
    }

    var notConfigured: String {
        isChinese ? "尚未配置" : "Not configured"
    }

    var secretaryLabel: String {
        isChinese ? "秘书" : "Secretary"
    }

    var summarizeButton: String {
        isChinese ? "总结" : "Summarize"
    }

    var summarizingButton: String {
        isChinese ? "总结中" : "Summarizing..."
    }

    var consolidateButton: String {
        isChinese ? "汇总" : "Consolidate"
    }

    var consolidatingButton: String {
        isChinese ? "汇总中" : "Consolidating..."
    }

    var submitButton: String {
        isChinese ? "提交" : "Submit"
    }

    var supplementButton: String {
        isChinese ? "补充" : "Supplement"
    }

    var speakButton: String {
        isChinese ? "发言" : "Speak"
    }

    var uploadButton: String {
        isChinese ? "上传" : "Upload"
    }

    var copyCurrentRound: String {
        isChinese ? "复制当前轮对话" : "Copy Current Round"
    }

    var copyCurrentRoundHelp: String {
        isChinese ? "复制当前轮对话" : "Copy current round conversation"
    }

    // MARK: - AI 状态

    var statusAway: String {
        isChinese ? "暂离" : "Away"
    }

    var statusPresent: String {
        isChinese ? "参会" : "Present"
    }

    var statusThinking: String {
        isChinese ? "思考中" : "Thinking"
    }

    var statusSpeaking: String {
        isChinese ? "发言中" : "Speaking"
    }

    var notAttending: String {
        isChinese ? "未参会" : "Not attending"
    }

    // MARK: - 系统消息气泡

    var secretarySummaryTitle: String {
        isChinese ? "秘书汇总如下：" : "Secretary Summary:"
    }

    var thinkingBubble: String {
        isChinese ? "思考" : "Thinking"
    }

    var speakingBubble: String {
        isChinese ? "发言" : "Speaking"
    }

    // MARK: - 气泡按钮提示

    var copiedTooltip: String {
        isChinese ? "已复制" : "Copied"
    }

    var copyContentTooltip: String {
        isChinese ? "复制内容" : "Copy Content"
    }

    // MARK: - 系统消息（B1 阶段进度）

    var buildingIndexProgress: String {
        isChinese ? "⏳ 正在构建文档索引…" : "⏳ Building document index..."
    }

    func collectingStatementsProgress(_ completed: Int, _ total: Int) -> String {
        isChinese
            ? "秘书正在收集各参会AI的最终论述…（\(completed)/\(total)）"
            : "Secretary is collecting final statements from participating AIs... (\(completed)/\(total))"
    }

    var secretarySummarizing: String {
        isChinese ? "秘书正在汇总…" : "Secretary is summarizing..."
    }

    var retryingSecretarySummary: String {
        isChinese ? "🔄 正在重试秘书汇总…" : "🔄 Retrying secretary summary..."
    }

    func resumeMeetingHistory(_ topic: String, _ count: Int) -> String {
        isChinese
            ? "已恢复会议：\(topic)（共 \(count) 条历史消息），正在准备继续开会..."
            : "Meeting restored: \(topic) (\(count) historical messages), preparing to continue..."
    }

    func resumeMeetingNoHistory(_ topic: String) -> String {
        isChinese
            ? "已恢复会议：\(topic)（未找到历史对话），正在准备继续开会..."
            : "Meeting restored: \(topic) (no historical conversation found), preparing to continue..."
    }

    var historySummaryGenerated: String {
        isChinese
            ? "✅ 历史总结已生成，正在给参会者注入记忆..."
            : "✅ Historical summary generated, injecting memory into participants..."
    }

    // MARK: - 系统消息（B2 成功确认）

    var indexBuildComplete: String {
        isChinese ? "✅ 文档索引构建完成。" : "✅ Document index build complete."
    }

    var roundSummarySaved: String {
        isChinese ? "✅ 本轮总结已成功保存" : "✅ Round summary saved successfully."
    }

    var roundRecordSaved: String {
        isChinese ? "✅ 本轮会议记录已安全保存。" : "✅ Round meeting record saved securely."
    }

    var finalStatementsSubmitted: String {
        isChinese
            ? "✅ 最终论述已提交，各参会 AI 已获悉本轮讨论结论。您可以发起新一轮讨论。"
            : "✅ Final statements submitted. All participating AIs have been informed of this round's conclusions. You may start a new round of discussion."
    }

    func filesUploaded(_ count: Int) -> String {
        isChinese ? "✅ \(count) 个文件上传成功。" : "✅ \(count) file(s) uploaded successfully."
    }

    func filesUploadFailed(_ count: Int) -> String {
        isChinese ? "⚠️ \(count) 个文件上传失败。" : "⚠️ \(count) file(s) failed to upload."
    }

    var resumeReady: String {
        isChinese ? "✅ 续会准备完成，您可以开始发言了" : "✅ Resume preparation complete. You may start speaking now."
    }

    var allParticipantsReady: String {
        isChinese
            ? "✅ 所有参会者已准备就绪，您可以开始发言了"
            : "✅ All participants are ready. You may start speaking now."
    }

    func meetingEndedArchivePath(_ path: String) -> String {
        isChinese
            ? "✅ 会议已结束，完整纪要已保存至：\n\(path)"
            : "✅ Meeting ended. Complete minutes saved at:\n\(path)"
    }

    // MARK: - 系统消息（B3 警告错误）

    var storageAccessFailed: String {
        isChinese ? "⚠️ 无法访问存储目录，文件上传失败。" : "⚠️ Cannot access storage directory. File upload failed."
    }

    func indexBuildFailed(_ desc: String) -> String {
        isChinese ? "⚠️ 文档索引构建失败：\(desc)" : "⚠️ Document index build failed: \(desc)"
    }

    func summarySaveFailed(_ desc: String) -> String {
        isChinese ? "⚠️ 总结保存失败：\(desc)" : "⚠️ Summary save failed: \(desc)"
    }

    func aiCallFailed(_ desc: String) -> String {
        isChinese ? "AI调用失败：\(desc)" : "AI call failed: \(desc)"
    }

    func roundRecordSaveFailed(_ desc: String) -> String {
        isChinese ? "⚠️ 本轮会议记录保存失败：\(desc)" : "⚠️ Round meeting record save failed: \(desc)"
    }

    func meetingEndArchiveFailed(_ desc: String) -> String {
        isChinese
            ? "⚠️ 会议已结束，但生成纪要失败：\(desc)"
            : "⚠️ Meeting ended, but minutes generation failed: \(desc)"
    }

    func memoryInjectionFailed(_ desc: String) -> String {
        isChinese ? "⚠️ 记忆注入失败：\(desc)" : "⚠️ Memory injection failed: \(desc)"
    }

    func resumeFailed(_ desc: String) -> String {
        isChinese ? "续开失败：\(desc)" : "Resume failed: \(desc)"
    }

    // MARK: - 系统消息（B4 引导操作）

    var pleaseCreateMeeting: String {
        isChinese ? "请先新建一个会议，确定会议主题。" : "Please create a meeting first and set a topic."
    }

    var noAIToSummarize: String {
        isChinese ? "当前没有 AI 参会，无法执行总结操作。" : "No AI is currently participating. Cannot perform summary."
    }

    var noHistoryToSummarize: String {
        isChinese ? "当前无对话历史，请先发起至少一轮讨论后再总结。" : "No conversation history. Please start at least one round of discussion before summarizing."
    }

    var aiNotConfigured: String {
        isChinese
            ? "该参会AI未配置，请前往设置界面完成API配置后再邀请参会。"
            : "This participant AI is not configured. Please complete API configuration in Settings before inviting."
    }

    var noAIToSpeak: String {
        isChinese
            ? "尚未有任何 AI 参会，请在左侧面板中点击 AI 状态按钮邀请其加入会议。"
            : "No AI has joined yet. Please click the AI status button in the left panel to invite them."
    }

    var aiSpeakingWait: String {
        isChinese
            ? "当前有 AI 正在发言，请等待发言结束后再汇总。"
            : "An AI is currently speaking. Please wait until the speech ends before consolidating."
    }

    var noHistoryToConsolidate: String {
        isChinese
            ? "当前无对话历史，请先发起至少一轮讨论后再汇总。"
            : "No conversation history. Please start at least one round of discussion before consolidating."
    }

    var waitBeforeEndMeeting: String {
        isChinese
            ? "请等待所有AI发言结束后再结束会议。"
            : "Please wait for all AIs to finish speaking before ending the meeting."
    }

    var meetingEndedNotice: String {
        isChinese ? "会议已结束。" : "Meeting ended."
    }

    var endMeetingPrompt: String {
        isChinese
            ? "本轮会议内容尚未总结，结束会议将无法保存对话内容。\n\n[📝 总结并结束会议](nm://end-summarize)　[🚪 直接结束会议](nm://end-force)"
            : "This round has not been summarized yet. Ending the meeting will lose the conversation content.\n\n[📝 Summarize & End](nm://end-summarize)　[🚪 End Directly](nm://end-force)"
    }

    // MARK: - 顶部提示（R1 拒绝操作）

    func createMeetingFailed(_ desc: String) -> String {
        isChinese ? "创建会议失败：\(desc)" : "Create meeting failed: \(desc)"
    }

    var waitAllSpeakersBeforeSummary: String {
        isChinese
            ? "请等待全部参会者发言结束后再执行总结操作"
            : "Please wait for all participants to finish speaking before summarizing."
    }

    var secretaryConsolidatingNoSummary: String {
        isChinese
            ? "秘书正在进行汇总，本轮对话无需再次总结"
            : "The Secretary is consolidating. No need to summarize this round again."
    }

    var summaryDoneUseConsolidate: String {
        isChinese
            ? "本轮总结已完毕，如果您希望补充意见并继续讨论，请点击汇总"
            : "This round's summary is complete. If you wish to add comments and continue, please click Consolidate."
    }

    var aiProcessingWait: String {
        isChinese
            ? "⚠️ 当前有AI正在处理，请等待完成后再复制"
            : "⚠️ An AI is currently processing. Please wait until complete before copying."
    }

    var waitSecretaryConsolidating: String {
        isChinese
            ? "秘书正在汇总中，请等待汇总完成后再结束会议"
            : "The Secretary is consolidating. Please wait until consolidation is complete before ending the meeting."
    }

    var waitSummaryInProgress: String {
        isChinese
            ? "总结正在进行中，请等待总结完成后再结束会议"
            : "Summary is in progress. Please wait until complete before ending the meeting."
    }

    var ragProcessingWait: String {
        isChinese
            ? "⚠️ 当前正在处理上传的文档，请等待处理完成后再发言"
            : "⚠️ Currently processing uploaded documents. Please wait until complete before speaking."
    }

    var endMethodAlreadySelected: String {
        isChinese
            ? "您已选择了结束会议的方式，请等待完成"
            : "You have already selected a way to end the meeting. Please wait for completion."
    }

    // MARK: - 顶部提示（R2 成功确认）

    var copiedToClipboard: String {
        isChinese ? "✅ 当前轮对话已复制到剪贴板" : "✅ Current round conversation copied to clipboard"
    }

    // MARK: - 侧面面板

    func userLabel(_ name: String) -> String {
        let prefix = isChinese ? "👤 用户" : "👤 User"
        return name.isEmpty ? prefix : "\(prefix)：\(name)"
    }

    // MARK: - 秘书展示

    var secretaryDisplayDefault: String {
        isChinese ? "秘书汇总如下：" : "Secretary Summary:"
    }

    func secretarySupplement(_ supplement: String) -> String {
        isChinese
            ? "\n\n---\n\n**用户补充意见：**\n\n\(supplement)"
            : "\n\n---\n\n**User Supplement:**\n\n\(supplement)"
    }

    func secretaryMoreOpinion(_ userName: String) -> String {
        let name = userName.isEmpty
            ? (isChinese ? "用户" : "User")
            : userName
        return isChinese
            ? "\n\n---\n\n亲爱的\(name)，您还需要补充其他意见吗？"
            : "\n\n---\n\nDear \(name), would you like to add any other comments?"
    }

    // MARK: - 复制对话

    func userSpoke(_ content: String) -> String {
        isChinese ? "用户 发言：\n【\(content)】\n\n" : "User spoke:\n【\(content)】\n\n"
    }

    func aiThought(_ name: String, _ content: String) -> String {
        isChinese ? "\(name) 思考：\n【\(content)】\n\n" : "\(name) thought:\n【\(content)】\n\n"
    }

    func secretarySpoke(_ content: String) -> String {
        isChinese ? "秘书 发言：\n【\(content)】\n\n" : "Secretary spoke:\n【\(content)】\n\n"
    }

    func aiSpoke(_ name: String, _ content: String) -> String {
        isChinese ? "\(name) 发言：\n【\(content)】\n\n" : "\(name) spoke:\n【\(content)】\n\n"
    }

    // MARK: - 盲评

    var opinionLabels: [String] {
        isChinese ? ["观点A", "观点B", "观点C"] : ["View A", "View B", "View C"]
    }

    var userSupplementLabel: String {
        isChinese ? "用户补充意见" : "User Supplement"
    }

    var finalStatementGenerationFailed: String {
        isChinese ? "最终论述生成失败：\("")" : "Final statement generation failed"
    }

    // MARK: - 会议结束

    func roundSummaryHeader(_ round: Int) -> String {
        isChinese ? "第\(round)轮汇总：\n" : "Round \(round) Summary:\n"
    }

    var unnamedMeeting: String {
        isChinese ? "未命名会议" : "Unnamed Meeting"
    }

    // MARK: - 系统对话消息 sender

    var systemSender: String {
        isChinese ? "系统" : "System"
    }

    // MARK: - 思考/发言后缀

    var thinkingSuffix: String {
        isChinese ? " · 思考" : " · Thinking"
    }

    var thinkingProgressSuffix: String {
        isChinese ? " 正在思考…" : " is thinking..."
    }

    var speakingProgressSuffix: String {
        isChinese ? " 正在发言…" : " is speaking..."
    }

    var aiPreparingToSpeak: String {
        isChinese ? "AI 正在准备发言…" : "AI is preparing to speak..."
    }

    var collectingFinalStatements: String {
        isChinese ? "正在收集各 AI 最终论述…" : "Collecting final statements from AIs..."
    }

    // MARK: - RAG 参考资料标签

    func referenceFromDocument(_ fileName: String, _ index: Int) -> String {
        isChinese
            ? "[参考资料] 以下内容来自您指定的「\(fileName)」（第\(index + 1) 份上传文档）：\n\n"
            : "[Reference] The following content is from the document you specified「\(fileName)」(uploaded document #\(index + 1)):\n\n"
    }

    var referenceFromDocuments: String {
        isChinese
            ? "[参考资料] 以下内容来自用户上传的文档：\n\n"
            : "[Reference] The following content is from user-uploaded documents:\n\n"
    }

    // MARK: - 最终论述收集

    func noContentForName(_ name: String) -> String {
        isChinese ? "### \(name)\n\n(无内容)" : "### \(name)\n\n(No content)"
    }

    var secretarySummaryFailed: String {
        isChinese ? "秘书汇总失败" : "Secretary Summary Failed"
    }

    var participantsSummaryHeader: String {
        isChinese ? "参会方论述汇总：" : "Participant Statements Summary:"
    }

    var systemReferencePrefix: String {
        isChinese ? "[参考资料] 以下内容来自您指定的文档：\n\n" : "[Reference] The following content is from your specified documents:\n\n"
    }

    // MARK: - 用户发言前缀

    var userStatementHeader: String {
        isChinese ? "## 用户发言\n\n" : "## User Statement\n\n"
    }

    // MARK: - 历史记忆注入

    var memoryInjectionPrompt: String {
        isChinese
            ? "这是本次会议之前的讨论情况和你之前的最后一次发言，你要充分了解并作为你的上文记忆，但这次回复时（仅仅是这次回复）不要对你收到的材料进行任何展开讨论，仅仅回复「我准备好继续开会了」即可。"
            : "This is the previous discussion and your last statement from this meeting. You should fully understand this and treat it as context memory. However, for this reply only, do not elaborate on the material you received. Simply reply with 'I am ready to continue the meeting.'"
    }

    var historicalMeetingSummaryLabel: String {
        isChinese ? "历史会议总结" : "Historical Meeting Summary"
    }

    var yourLastStatementLabel: String {
        isChinese ? "你最后一次发言" : "Your Last Statement"
    }

    var memoryInjectionInitialSystem: String {
        isChinese
            ? "你正在参加一场会议，请严格按照用户的要求回复"
            : "You are participating in a meeting. Please reply strictly according to the user's request."
    }

    var readyToContinueResponse: String {
        isChinese ? "我准备好继续开会了" : "I am ready to continue the meeting."
    }

    // MARK: - 历史秘书归纳

    func historyNoContentFallback(_ topic: String) -> String {
        isChinese
            ? "会议主题：\(topic)\n讨论方向：无\n历史结论：无"
            : "Meeting Topic: \(topic)\nDiscussion Direction: None\nHistorical Conclusion: None"
    }

    var historySecretaryPrompt: String {
        isChinese
            ? """
            请你作为会议秘书，基于以下所有轮次的会议匿名汇总内容，归纳总结出本次会议的核心信息：
            要求：
            1. 输出三段内容，分别是【会议主题】【讨论方向】【历史结论】
            2. 语言简洁，核心信息完整，不要多余内容
            3. 完全基于提供的汇总内容，不要添加任何虚构信息
            4. 保持匿名，不要提及任何参会者名字

            以下是历史汇总内容：
            """
            : """
            As the meeting secretary, please summarize the core information of this meeting based on all the following round summaries:
            Requirements:
            1. Output three sections: [Meeting Topic], [Discussion Direction], [Historical Conclusion]
            2. Be concise, include all core information, no unnecessary content
            3. Base entirely on the provided summaries, do not add any fabricated information
            4. Keep anonymity, do not mention any participant names

            Below are the historical summaries:
            """
    }

    var historySecretarySystem: String {
        isChinese
            ? "你是专业的会议秘书，擅长归纳总结会议核心内容"
            : "You are a professional meeting secretary, skilled at summarizing core meeting content."
    }

    // MARK: - 总结流程

    var summaryProcessSystemPrompt: String {
        isChinese
            ? "以下是本轮会议用户发言及各参会AI的最终论述：\n\n"
            : "Below are the user statements and final arguments from each participating AI in this round:\n\n"
    }

    // MARK: - 动画/日志

    var aiCallFailedLogPrefix: String {
        isChinese ? "⚠️ AI调用失败" : "⚠️ AI call failed"
    }

    var saveConversationFailed: String {
        isChinese ? "保存对话失败" : "Failed to save conversation"
    }

    var saveMeetingStateFailed: String {
        isChinese ? "保存会议状态失败" : "Failed to save meeting state"
    }

    var saveConfigSnapshotFailed: String {
        isChinese ? "保存会议配置快照失败" : "Failed to save meeting config snapshot"
    }

    // MARK: - 系统提示词（四大核心 Prompt）

    var systemPrompt: String {
        isChinese
            ? """
            你正在参加一场深度交流会议。请严格围绕用户提出的话题，做出正式发言。
            原则：
            - 理性、严谨、客观地回应用户的发言，从多角度给出有深度、有依据的见解。
            - 避免空洞的社交性附和。表达赞同应有具体的分析依据支撑，而非单纯的立场认同。
            - 保持逻辑自洽，拥有大局观，实事求是，避免空洞的自信。
            - 发言应基于可验证的事实和逻辑推导，而非身份或权威。
            - 如果存在不确定性，请明确指出假设和风险的边界。
            - 不要自行发起新议题，不要编造不存在的数据或场景，不要假设用户没提出的背景信息。
            - 如果用户的问题不明确，请请求澄清，而不是自行脑补。
            - 发言请使用标准 Markdown 格式。段落之间用空行分隔。如需列举要点，请使用 - 或 1. 等列表语法，不要用纯文本序数词替代。
            """
            : """
            You are participating in an in-depth discussion meeting. Please speak formally, strictly focusing on the topic raised by the user.
            Principles:
            - Respond rationally, rigorously, and objectively to the user's statements, providing deep, evidence-based insights from multiple perspectives.
            - Avoid hollow social pleasantries. Agreement should be supported by concrete analytical reasoning, not mere position alignment.
            - Maintain logical consistency and a big-picture perspective. Be factual and practical, avoiding empty confidence.
            - Statements should be based on verifiable facts and logical deduction, not identity or authority.
            - If there is uncertainty, clearly indicate the boundaries of assumptions and risks.
            - Do not initiate new topics, fabricate non-existent data or scenarios, or assume background information the user has not provided.
            - If the user's question is unclear, request clarification rather than filling in gaps yourself.
            - Use standard Markdown format for your statements. Separate paragraphs with blank lines. When listing points, use - or 1. list syntax.
            """
    }

    var secretarySystemPrompt: String {
        isChinese
            ? """
            你是AI会议室的专职秘书，你为用户服务。你的职责是：
            1. 完整保留用户发言原文，置顶于汇总稿最前面，格式为「## 用户发言\\n\\n[原文]」。
            2. 将各参会AI的论述按「AI 名称 + 核心论点 + 关键论据 + 论述原文」的格式逐一整理。
            3. 最后附一段「分歧点总结」。按以下格式列出：
               - 一致点：各AI论述中实质相同的观点
               - 差异点：各AI之间表述明显不同的观点（只陈述差异，不评价）
            4. 输出内容必须使用标准 Markdown 格式，段落间空行分隔。
            5. 只基于收到的原文进行汇总，严禁添加原文中没有的新观点、新数据或新场景。
            """
            : """
            You are the dedicated secretary of this AI meeting room, serving the user. Your responsibilities are:
            1. Preserve the user's original statement in full, placing it at the top of the summary in the format "## User Statement\\n\\n[Original text]".
            2. Organize each participating AI's statements in the format: "AI Name + Core Argument + Key Evidence + Original Statement".
            3. Append a "Summary of Diverging Points" section. List as follows:
               - Points of Agreement: Views that are substantively identical across AI statements
               - Points of Divergence: Views that are clearly different across AI statements (state differences only, without evaluation)
            4. Output must use standard Markdown format, with blank lines separating paragraphs.
            5. Base your summary solely on the original statements received. Do not add any new viewpoints, data, or scenarios not present in the originals.
            """
    }

    var finalStatementPrompt: String {
        isChinese
            ? """
            请基于本轮你与用户的所有对话上下文，输出你当前阶段的最终论述。要求：
            1. 用一段话概括你的核心观点。
            2. 列出支撑该观点的关键论据（使用 - 列表）。
            3. 如有不确定性，请在文末明确指出假设边界和风险。
            4. 不要引入本论述前未提及的新话题、新数据或新场景。
            5. 严格按「核心论点 + 关键论据 + 论述原文」的格式组织论述。
            6. 输出内容必须使用标准 Markdown 格式，段落间空行分隔。
            """
            : """
            Based on all your conversation context with the user in this round, output your final statement for the current phase. Requirements:
            1. Summarize your core viewpoint in one paragraph.
            2. List the key evidence supporting this viewpoint (using - list format).
            3. If there is uncertainty, clearly state the boundaries of assumptions and risks at the end.
            4. Do not introduce new topics, data, or scenarios not previously discussed.
            5. Strictly organize in the format: "Core Argument + Key Evidence + Original Statement".
            6. Output must use standard Markdown format, with blank lines separating paragraphs.
            """
    }

    var summarizationPrompt: String {
        isChinese
            ? """
            【当前任务特殊规则】
            用户当前的问题是文档概括类需求，请严格遵守以下规则：
            1. 如果用户明确指定了某份文档，请仅基于该文档的内容概括，完全不要参考其他文档的信息。
            2. 如果用户要求概括所有文档，或者没有明确指定目标文档，请分别概括每份文档的核心内容，每份单独成段，开头加上「【文档X：文件名】」的标识，不要把多份文档内容混在一起概括。
            3. 不要编造文档里没有的数据、场景、背景信息。如果某部分存在不确定性，请明确指出边界。
            4. 如果用户的目标不明确（比如有多份文档但未指定概括哪一份），请主动请求澄清，而不是自行脑补。
            5. 回答请使用标准 Markdown 格式，段落之间用空行分隔，结构清晰、重点突出。
            """
            : """
            [Special Rules for Current Task]
            The user's current query involves document summarization. Please strictly follow these rules:
            1. If the user has explicitly specified a document, summarize based solely on that document's content. Do not reference information from other documents.
            2. If the user requests summarization of all documents, or has not specified a target document, summarize each document's core content separately. Place each in its own section, prefixed with "[Document X: filename]". Do not mix content from multiple documents together.
            3. Do not fabricate data, scenarios, or background information not present in the documents. If there is uncertainty in any part, clearly indicate the boundaries.
            4. If the user's intent is unclear (e.g., multiple documents exist but no specific one is designated for summarization), proactively request clarification rather than making assumptions.
            5. Use standard Markdown format for your response, with blank lines separating paragraphs. Structure should be clear and focused.
            """
    }

    // MARK: - 会议流程图

    var flowchartTitle: String {
        isChinese ? "会议流程" : "Meeting Flow"
    }

    var flowNodeUserSpeak: String {
        isChinese ? "用户发言" : "User Speaks"
    }

    var flowNodeRAG: String {
        isChinese ? "RAG检索注入" : "RAG Retrieval"
    }

    var flowNodeAISpeak: String {
        isChinese ? "AI依次发言" : "AI Speaks in Turn"
    }

    var flowNodeSupplement: String {
        isChinese ? "用户补充意见" : "User Supplement"
    }

    var flowNodeBlindReview: String {
        isChinese ? "匿名盲评" : "Anonymous Blind Review"
    }

    var flowNodeRoundPlus: String {
        isChinese ? "轮次+1" : "Round +1"
    }

    var flowNodeEndMeeting: String {
        isChinese ? "结束会议" : "End Meeting"
    }

    var flowArrowSyncToAI: String {
        isChinese ? "同步到所有AI" : "Sync to All AIs"
    }

    var flowArrowInjectContext: String {
        isChinese ? "注入上下文" : "Inject Context"
    }

    var flowArrowSecretarySummary: String {
        isChinese ? "秘书汇总分歧" : "Secretary Summarizes"
    }

    var flowArrowAnonymize: String {
        isChinese ? "匿名化处理" : "Anonymization"
    }

    var flowArrowArchiveHistory: String {
        isChinese ? "历史归档" : "History Archive"
    }

    var flowArrowEndArchive: String {
        isChinese ? "结束归档" : "Final Archive"
    }

    var flowBranchSummary: String {
        isChinese ? "总结" : "Summary"
    }

    var flowBranchWhisper: String {
        isChinese ? "悄悄问秘书" : "Whisper to Secretary"
    }

    var flowBranchResume: String {
        isChinese ? "历史会议续开" : "Resume Meeting"
    }

    var flowWhisperIndependent: String {
        isChinese ? "🔒 完全独立通道" : "🔒 Independent Channel"
    }

    var flowResumeInherit: String {
        isChinese ? "继承历史轮次" : "Inherit History"
    }

    var flowLoopNewRound: String {
        isChinese ? "新一轮" : "New Round"
    }

    var flowLoopDiscussion: String {
        isChinese ? "讨论" : "Discussion"
    }

    var flowLegendUser: String {
        isChinese ? "用户" : "User"
    }

    var flowLegendAI: String {
        isChinese ? "AI" : "AI"
    }

    var flowLegendSecretary: String {
        isChinese ? "秘书" : "Secretary"
    }

    var flowLegendSystem: String {
        isChinese ? "系统" : "System"
    }

    var flowLegendSummary: String {
        isChinese ? "总结" : "Summary"
    }

    var flowLegendDone: String {
        isChinese ? "完成" : "Complete"
    }

    var flowLegendMainFlow: String {
        isChinese ? "主流程" : "Main Flow"
    }

    var flowLegendLoopPath: String {
        isChinese ? "循环路径" : "Loop Path"
    }

    var flowLegendIndependent: String {
        isChinese ? "独立功能" : "Independent"
    }

    // MARK: - 帮助窗口

    var helpWindowTitle: String {
        isChinese ? "Normal Meeting 帮助" : "Normal Meeting Help"
    }

    var helpSectionRoundtable: String {
        isChinese ? "👥 圆桌会议" : "👥 Roundtable"
    }

    var helpSectionCoreFlow: String {
        isChinese ? "🚀 核心流程" : "🚀 Core Flow"
    }

    var helpSectionRAG: String {
        isChinese ? "📄 文档检索（RAG）" : "📄 Document Retrieval (RAG)"
    }

    var helpSectionWhisper: String {
        isChinese ? "🤫 悄悄问秘书" : "🤫 Whisper to Secretary"
    }

    var helpSectionSummaryVsConsolidate: String {
        isChinese ? "📋 总结 vs 汇总" : "📋 Summary vs Consolidation"
    }

    var helpSectionHistoryResume: String {
        isChinese ? "🔄 历史会议续开" : "🔄 Resume Meeting"
    }

    var helpSectionShortcuts: String {
        isChinese ? "⚙️ 快捷键" : "⚙️ Shortcuts"
    }

    var helpSectionSecurity: String {
        isChinese ? "🔒 安全说明" : "🔒 Security"
    }

    // MARK: - 概括类触发词

    var docReferenceWords: [String] {
        isChinese
            ? ["文档", "文件", "材料"]
            : ["document", "documents", "file", "files", "material", "materials", "upload", "uploaded", "attachment", "attachments"]
    }

    var summaryTriggerWords: [String] {
        isChinese
            ? ["概括", "总结", "讲什么", "内容是什么", "核心内容", "核心信息", "介绍", "理解", "了解", "看法", "观点", "分析", "评价", "解读"]
            : [
                "summarize", "summary", "summarization",
                "recap", "conclude", "conclusion",
                "what is it about", "what does it say", "what's in it",
                "what is the content", "what is the content of",
                "core content", "main content", "key content",
                "key information", "core information", "main points",
                "introduce", "describe", "tell me about", "tell me what",
                "understand", "comprehend",
                "know about", "learn about", "overview", "overview of",
                "opinion", "opinion on", "view on", "take on",
                "viewpoint", "perspective", "point of view",
                "analyze", "analysis",
                "evaluate", "evaluation", "assess", "review",
                "interpret", "interpretation", "explain", "explanation"
            ]
    }

    // MARK: - 文档匹配正则模式

    var documentNumberPattern: String {
        isChinese
            ? "(?:文档|文件|第)\\s*(\\d+)\\s*(?:份|个|篇)?"
            : "(?:document|file|doc)\\s*(?:#|number|no\\.?)?\\s*(\\d+)(?:st|nd|rd|th)?"
    }

    var chineseNumberPattern: String {
        "第([一二三四五六七八九十]+)(?=份|个|篇|文档|文件)"
    }

    // MARK: - RAG 触发词（shouldTriggerRAG）

    var ragTriggerDocWords: [String] {
        isChinese
            ? ["文档", "文件", "材料", "这份", "那份", "这份文档", "那份文档", "上传", "这些文档", "那些文档"]
            : ["document", "documents", "file", "files", "material", "materials", "upload", "uploaded", "attachment", "this document", "that document", "these documents"]
    }

    var ragTriggerQuestionWords: [String] {
        isChinese
            ? ["什么", "怎么", "如何", "为什么", "哪个", "哪些", "谁", "哪里", "何时"]
            : ["what", "how", "why", "which", "who", "where", "when", "whose"]
    }

    var ragTriggerActionWords: [String] {
        isChinese
            ? ["分析", "总结", "对比", "评价", "优化", "检查", "帮我", "建议", "方案", "思路", "区别", "差异", "优势", "劣势", "问题", "修改", "改进", "解释", "解读", "介绍", "概括"]
            : ["analyze", "analysis", "summarize", "summary", "compare", "comparison", "contrast", "evaluate", "review", "check", "help", "suggest", "suggestion", "plan", "approach", "idea", "difference", "differences", "advantage", "disadvantage", "problem", "issue", "improve", "improvement", "explain", "explanation", "interpret", "describe", "description", "recap", "overview"]
    }
}
