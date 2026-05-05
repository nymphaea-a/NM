import SwiftUI
import AppKit

// MARK: - 消息模型

struct Message: Identifiable {
    let id = UUID()
    let sender: String
    var content: String
    let isUser: Bool
    var timerSuffix: String? = nil
}

// MARK: - Token 缓冲器

class TokenBuffer {
    private var reasoningBuffer = ""
    private var contentBuffer = ""
    private var lastReasoningFlush = Date()
    private var lastContentFlush = Date()
    private let flushInterval: TimeInterval = 0.15

    let onFlush: (String, String) -> Void

    init(onFlush: @escaping (String, String) -> Void) {
        self.onFlush = onFlush
    }

    func append(reasoning: String, content: String) {
        if !reasoning.isEmpty {
            reasoningBuffer += reasoning
        }
        if !content.isEmpty {
            contentBuffer += content
        }
        let now = Date()
        if now.timeIntervalSince(lastReasoningFlush) >= flushInterval ||
           now.timeIntervalSince(lastContentFlush) >= flushInterval {
            flush()
        }
    }

    func complete() {
        flush()
    }

    private func flush() {
        let r = reasoningBuffer
        let c = contentBuffer
        reasoningBuffer = ""
        contentBuffer = ""
        lastReasoningFlush = Date()
        lastContentFlush = Date()
        if !r.isEmpty || !c.isEmpty {
            onFlush(r, c)
        }
    }
}

// MARK: - 参会者模型（仅含运行时状态）

struct Participant: Identifiable {
    let id = UUID()
    let index: Int              // 对应 Config.shared.participants 的索引
    var status: AIStatus = .away
    var accumulatedTokens: Int = 0
}

enum AIStatus {
    case away
    case present
    case thinking
    case speaking
}

// MARK: - Secretary 阶段枚举

enum SecretaryPhase {
    case idle
    case collecting
    case summarizing
    case done
}

// MARK: - 消息历史编辑器（NSTextView wrapper，修复中文输入法问题）

struct GrowingTextEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.backgroundColor = .clear
        textView.drawsBackground = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        let parent: GrowingTextEditor

        init(_ parent: GrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    // ──────────────── 基础状态 ────────────────
    @State var messages: [Message] = []
    @State var inputText: String = ""
    @State var currentSpeaker: String = ""
    @State var isStreaming = false
    @State var currentStreamMessageID: UUID? = nil

    // ──────────────── 参会者 ────────────────
    @State var participants: [Participant] = (0..<Config.shared.participants.count).map {
        Participant(index: $0)
    }
    let secretaryIndex = -1  // 秘书用 -1 标记

    // ──────────────── AI 独立消息历史 ────────────────
    @State var aiMessageHistories: [String: [[String: String]]] = [:]

    // ──────────────── 秘书汇总状态 ────────────────
    @State var secretaryPhase: SecretaryPhase = .idle
    @State var secretaryBaseContent: String = ""
    @State var secretaryMessageID: UUID? = nil
    @State var userSupplement: String = ""

    // ──────────────── 最终论述收集 ────────────────
    @State var finalStatements: [String: String] = [:]
    @State var pendingAIOrder: [Participant] = []
    @State var secretaryStartTime: Date? = nil
    @State var currentProgressMessageID: UUID? = nil
    @State var secretaryCollectCompleted: Int = 0
    @State var secretaryCollectTotal: Int = 0

    // ──────────────── 设置面板 ────────────────
    @State var showSettings = false

    // ──────────────── 常量 ────────────────
    let systemPrompt = """
    你是一个正在参加线上会议的 AI 助手。用户是会议主持人，与你及其他 AI 共同讨论。
    请根据会议上下文发言，保持简洁、有深度，并在适当的时候提出建设性意见。
    """

    let secretarySystemPrompt = """
    你是会议秘书，负责将各方论述汇总为结构化的会议纪要。
    请按以下格式输出：

    ## 各方核心观点
    分别列出每位参会者的核心观点（用观点A/B/C匿名化）。

    ## 共识点
    列出各方达成共识的内容。

    ## 分歧点总结
    分析各方观点的异同，指出主要分歧及潜在原因，并给出折中建议。

    注意：务必先完整展示各方观点，再进行分析。
    """

    let finalStatementPrompt = """
    会议主持人要求你针对刚才的讨论生成最终自我论述（匿名化），请遵循以下规则：

    1. 总结你的核心观点，表述清晰、有层次。
    2. 明确指出你在哪些点上同意或不同意其他观点（用观点A/B/C代指），并解释原因。
    3. 提出你认为最佳的折中方案或下一步行动建议。
    4. 不要提及你自己的名称或身份。
    """

    // ──────────────── 计算属性 ────────────────
    /// 该参会 AI 是否已配置（name 和 apiKey 均非空）
    func isConfigured(_ p: Participant) -> Bool {
        let cfg = Config.shared.participants[p.index]
        return !cfg.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // ──────────────── 视图 ────────────────
    var body: some View {
        HStack(spacing: 0) {
            // 左侧面板：参会列表
            sidebarView
                .frame(width: 220)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

            Divider()

            // 右侧：聊天 + 输入
            VStack(spacing: 0) {
                chatView
                inputView
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
    }

    // MARK: - 侧边栏

    var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("参会人员")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户
                    sidebarUserRow()

                    Divider().padding(.horizontal, 16)

                    // 参会 AI
                    ForEach($participants) { $p in
                        sidebarParticipantRow(p)
                    }

                    Divider().padding(.horizontal, 16)

                    // 秘书
                    sidebarSecretaryRow()
                }
            }

            Spacer()

            // 设置按钮
            HStack {
                Spacer()
                Button(action: { showSettings = true }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
    }

    func sidebarUserRow() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "person.circle")
                .font(.system(size: 22))
                .foregroundColor(.accentColor)
            Text(Config.shared.userName.isEmpty ? "我" : Config.shared.userName)
                .font(.body)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    func sidebarParticipantRow(_ p: Participant) -> some View {
        let cfg = Config.shared.participants[p.index]
        let configured = isConfigured(p)

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 22))
                    .foregroundColor(configured ? getStatusColor(p.status) : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(configured ? cfg.name : "空")
                        .font(.body)
                    if configured {
                        Text(cfg.model)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // 状态按钮
            HStack {
                Spacer()
                if configured {
                    Button(action: { toggleParticipantStatus(p) }) {
                        Label(
                            statusLabel(p.status),
                            systemImage: statusIcon(p.status)
                        )
                        .font(.caption)
                        .foregroundColor(statusButtonColor(p.status))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                } else {
                    Button(action: { showSettings = true }) {
                        Label("未配置", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    func sidebarSecretaryRow() -> some View {
        let secCfg = Config.shared.secretary
        let secConfigured = !secCfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundColor(secConfigured ? .accentColor : .secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("秘书")
                        .font(.body)
                    if secConfigured {
                        Text(secCfg.model)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if secConfigured {
                HStack {
                    Spacer()
                    Label("● 参会", systemImage: "person.fill.checkmark")
                        .font(.caption)
                        .foregroundColor(.green)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            } else {
                HStack {
                    Spacer()
                    Button(action: { showSettings = true }) {
                        Label("未配置", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - 状态辅助方法

    func statusLabel(_ status: AIStatus) -> String {
        switch status {
        case .away:     return "暂离"
        case .present:  return "参会"
        case .thinking: return "思考中"
        case .speaking: return "发言中"
        }
    }

    func statusIcon(_ status: AIStatus) -> String {
        switch status {
        case .away:     return "circle"
        case .present:  return "circle.fill"
        case .thinking: return "ellipsis.circle"
        case .speaking: return "waveform.circle"
        }
    }

    func getStatusColor(_ status: AIStatus) -> Color {
        switch status {
        case .away:     return .secondary
        case .present:  return .green
        case .thinking: return .orange
        case .speaking: return .blue
        }
    }

    func statusButtonColor(_ status: AIStatus) -> Color {
        switch status {
        case .away:     return .secondary
        case .present:  return .green
        case .thinking: return .orange
        case .speaking: return .blue
        }
    }

    func toggleParticipantStatus(_ p: Participant) {
        guard let idx = participants.firstIndex(where: { $0.id == p.id }) else { return }
        switch participants[idx].status {
        case .away:
            participants[idx].status = .present
        case .present, .thinking, .speaking:
            participants[idx].status = .away
        }
    }

    // MARK: - 聊天区域

    var chatView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { msg in
                        MessageBubble(msg: msg, onRetry: {
                            handleRetrySummary()
                        })
                        .id(msg.id)
                    }
                }
                .padding()
            }
            .onChange(of: messages.count) { _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: messages.last?.content) { _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    func scrollToBottom(proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        withAnimation {
            proxy.scrollTo(last.id, anchor: .bottom)
        }
    }

    // MARK: - 消息气泡

    struct MessageBubble: View {
        let msg: Message
        let onRetry: () -> Void

        var body: some View {
            HStack(alignment: .top) {
                if msg.isUser {
                    Spacer()
                    userBubble
                } else {
                    aiBubble
                    Spacer()
                }
            }
        }

        var userBubble: some View {
            VStack(alignment: .trailing, spacing: 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(msg.sender)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SelectionText(content: msg.content)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.accentColor.opacity(0.15))
                    )
                }
            }
            .frame(minHeight: 24)
        }

        var aiBubble: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Text(msg.sender)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            if let suffix = msg.timerSuffix {
                                Text(suffix)
                                    .font(.caption2)
                                    .foregroundColor(.secondary.opacity(0.6))
                                    .monospacedDigit()
                            }
                        }
                        if msg.sender == "系统" && msg.content.contains("重试") {
                            VStack(alignment: .leading, spacing: 4) {
                                MarkdownText(content: msg.content)
                                Button("🔄 重试汇总") { onRetry() }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.orange)
                                    )
                                    .foregroundColor(.white)
                            }
                        } else {
                            MarkdownText(content: msg.content)
                        }
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                    )
                }
            }
            .frame(minHeight: 24)
        }
    }

    // MARK: - Markdown 渲染

    struct MarkdownText: View {
        let content: String

        var body: some View {
            if let attributed = try? AttributedString(
                markdown: content,
                options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed)
                    .textSelection(.enabled)
                    .font(.body)
            } else {
                Text(content)
                    .textSelection(.enabled)
                    .font(.body)
            }
        }
    }

    // MARK: - 可选文本（适配 SelectionText 缺失的情况）

    struct SelectionText: View {
        let content: String
        var body: some View {
            Text(content)
                .textSelection(.enabled)
                .font(.body)
        }
    }

    // MARK: - 输入区域

    var inputView: some View {
        VStack(spacing: 0) {
            Divider()

            // 当前发言者指示
            if !currentSpeaker.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                    Text(currentSpeaker)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }

            HStack(alignment: .bottom, spacing: 8) {
                GrowingTextEditor(text: $inputText)
                    .frame(minHeight: 40, maxHeight: 200)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                VStack(spacing: 6) {
                    // 提交按钮（done 阶段橙色可点击，其余阶段灰色禁用）
                    Button("提交") {
                        submitFinalStatements()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(secretaryPhase == .done ? Color.orange : Color.gray.opacity(0.35))
                    )
                    .foregroundColor(secretaryPhase == .done ? .white : Color.white.opacity(0.5))
                    .font(.body)
                    .disabled(secretaryPhase != .done)

                    Button(secretaryPhase == .done ? "补充" : "发言") {
                        handleInputSubmit()
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(inputButtonDisabled ? Color.gray.opacity(0.35) : Color.green)
                    )
                    .foregroundColor(inputButtonDisabled ? Color.white.opacity(0.5) : .white)
                    .disabled(inputButtonDisabled)
                }
            }
            .padding()
        }
        .frame(minHeight: 110, maxHeight: 380)
    }

    // MARK: - 辅助变量

    var inputButtonDisabled: Bool {
        let textEmpty = inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if secretaryPhase == .done {
            return textEmpty
        }
        return textEmpty || isStreaming || !currentSpeaker.isEmpty
    }

    // MARK: - 输入提交分发

    func handleInputSubmit() {
        if secretaryPhase == .done {
            submitSupplement()
        } else {
            sendMessage()
        }
    }

    // MARK: - 消息发送

    func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isStreaming else { return }

        // 检查是否有任何 AI 参会
        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            messages.append(Message(sender: "系统", content: "尚未有任何 AI 参会，请在左侧面板中点击 AI 状态按钮邀请其加入会议。", isUser: false))
            return
        }

        let userName = Config.shared.userName.isEmpty ? "我" : Config.shared.userName
        messages.append(Message(sender: userName, content: text, isUser: true))
        inputText = ""
        isStreaming = true

        currentSpeaker = "AI 正在准备发言…"

        // 收集所有参会的 AI
        let aiOrder = presentAIs

        // 将用户发言追加到每个参会 AI 的独立历史中
        for ai in aiOrder {
            let cfg = Config.shared.participants[ai.index]
            ensureHistory(for: cfg.name)
            aiMessageHistories[cfg.name]?.append(["role": "user", "content": text])
        }

        speakNext(aiOrder: aiOrder, index: 0)
    }

    // MARK: - 确保消息历史存在

    func ensureHistory(for name: String) {
        if aiMessageHistories[name] == nil {
            aiMessageHistories[name] = [["role": "system", "content": systemPrompt]]
        }
    }

    // MARK: - AI 依次发言

    func speakNext(aiOrder: [Participant], index: Int) {
        guard index < aiOrder.count else {
            currentSpeaker = ""
            isStreaming = false
            for ai in aiOrder {
                if let idx = participants.firstIndex(where: { $0.id == ai.id }) {
                    participants[idx].status = .present
                }
            }
            return
        }

        let ai = aiOrder[index]
        let cfg = Config.shared.participants[ai.index]
        ensureHistory(for: cfg.name)

        currentSpeaker = "\(cfg.name) 正在思考…"
        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
            participants[aiIndex].status = .thinking
        }

        let history = aiMessageHistories[cfg.name]!

        let thinkingMsg = Message(sender: "\(cfg.name) · 思考", content: "", isUser: false)
        messages.append(thinkingMsg)
        var replyCreated = false
        var hasSpoken = false

        let buffer = TokenBuffer { reasoning, content in
            DispatchQueue.main.async {
                if !reasoning.isEmpty {
                    if let index = messages.firstIndex(where: { $0.id == thinkingMsg.id }) {
                        messages[index].content += reasoning
                    }
                }
                if !content.isEmpty {
                    if !replyCreated {
                        replyCreated = true
                        let replyMsg = Message(sender: cfg.name, content: "", isUser: false)
                        messages.append(replyMsg)
                        currentStreamMessageID = replyMsg.id
                    }
                    if !hasSpoken {
                        hasSpoken = true
                        currentSpeaker = "\(cfg.name) 正在发言…"
                        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[aiIndex].status = .speaking
                        }
                    }
                    if let id = currentStreamMessageID,
                       let index = messages.firstIndex(where: { $0.id == id }) {
                        messages[index].content += content
                    }
                }
            }
        }

        APIService.callAIStream(
            config: cfg,
            messages: history,
            onToken: { tokenText, isReasoning in
                if isReasoning {
                    buffer.append(reasoning: tokenText, content: "")
                } else {
                    buffer.append(reasoning: "", content: tokenText)
                }
            },
            onComplete: { result in
                buffer.complete()
                DispatchQueue.main.async {
                    if let index = messages.firstIndex(where: { $0.id == thinkingMsg.id }),
                       messages[index].content.isEmpty {
                        messages.remove(at: index)
                    }
                    switch result {
                    case .failure(let error):
                        if replyCreated {
                            if let id = currentStreamMessageID,
                               let index = messages.firstIndex(where: { $0.id == id }) {
                                messages[index].content = "AI调用失败：\(error.localizedDescription)"
                            }
                        } else {
                            messages.append(Message(sender: "系统", content: "AI调用失败：\(error.localizedDescription)", isUser: false))
                        }
                        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[aiIndex].status = .away
                        }
                    case .success(let usage):
                        if let usage = usage, let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[aiIndex].accumulatedTokens += usage.total_tokens
                        }
                        if let id = currentStreamMessageID,
                           let index = messages.firstIndex(where: { $0.id == id }) {
                            let replyContent = messages[index].content
                            aiMessageHistories[cfg.name]?.append(
                                ["role": "assistant", "content": replyContent]
                            )
                        }
                        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[aiIndex].status = .present
                        }
                    }
                    currentStreamMessageID = nil
                    self.speakNext(aiOrder: aiOrder, index: index + 1)
                }
            }
        )
    }

    // MARK: - 秘书汇总触发

    func triggerSummary() {
        guard secretaryPhase == .idle else { return }

        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            messages.append(Message(sender: "系统", content: "尚未有任何 AI 参会，请在左侧面板中点击 AI 状态按钮邀请其加入会议。", isUser: false))
            return
        }

        guard !isStreaming, currentSpeaker.isEmpty else {
            messages.append(Message(sender: "系统", content: "当前有 AI 正在发言，请等待发言结束后再汇总。", isUser: false))
            return
        }

        let hasHistory = presentAIs.contains { ai in
            let cfg = Config.shared.participants[ai.index]
            guard let history = aiMessageHistories[cfg.name] else { return false }
            return history.contains { $0["role"] == "user" }
        }
        guard hasHistory else {
            messages.append(Message(sender: "系统", content: "当前无对话历史，请先发起至少一轮讨论后再汇总。", isUser: false))
            return
        }

        triggerFinalStatements(for: presentAIs)
    }

    // MARK: - 并行自我总结 + 秘书汇总

    func triggerFinalStatements(for aiOrder: [Participant]) {
        guard secretaryPhase == .idle else { return }
        secretaryPhase = .collecting
        pendingAIOrder = aiOrder
        secretaryStartTime = Date()

        for ai in aiOrder {
            if let idx = participants.firstIndex(where: { $0.id == ai.id }) {
                participants[idx].status = .thinking
            }
        }
        currentSpeaker = "正在收集各 AI 最终论述…"

        let t0 = String(format: "%.1fs", 0.0)
        var progressMsg = Message(sender: "系统", content: "秘书正在收集各参会AI的最终论述…（0/\(aiOrder.count)）", isUser: false)
        progressMsg.timerSuffix = t0
        messages.append(progressMsg)
        let progressID = progressMsg.id
        currentProgressMessageID = progressID
        secretaryCollectCompleted = 0
        secretaryCollectTotal = aiOrder.count

        Task {
            var collected: [String: String] = [:]
            var completedCount = 0

            await withTaskGroup(of: (String, Result<(String, TokenUsage?), Error>).self) { group in
                for ai in aiOrder {
                    let cfg = Config.shared.participants[ai.index]
                    group.addTask {
                        let history = await MainActor.run { aiMessageHistories[cfg.name] ?? [] }
                        var msgs = history
                        msgs.append(["role": "user", "content": finalStatementPrompt])

                        return await withCheckedContinuation { continuation in
                            APIService.callAI(config: cfg, messages: msgs, enableThinking: false) { result in
                                continuation.resume(returning: (cfg.name, result))
                            }
                        }
                    }
                }

                for await (name, result) in group {
                    await MainActor.run {
                        switch result {
                        case .success(let (content, usage)):
                            collected[name] = content
                            if let usage = usage {
                                totalInputTokens += usage.prompt_tokens
                                totalOutputTokens += usage.completion_tokens
                                if let pIdx = participants.firstIndex(where: { Config.shared.participants[$0.index].name == name }) {
                                    participants[pIdx].accumulatedTokens += usage.total_tokens
                                }
                            } else {
                                let estimatedOutput = Int(Double(content.count) / 2.5)
                                let history = aiMessageHistories[name] ?? []
                                let totalChars = history.reduce(0) { $0 + ($1["content"]?.count ?? 0) }
                                let estimatedInput = Int(Double(totalChars) / 2.5)
                                totalInputTokens += estimatedInput
                                totalOutputTokens += estimatedOutput
                                if let pIdx = participants.firstIndex(where: { Config.shared.participants[$0.index].name == name }) {
                                    participants[pIdx].accumulatedTokens += (estimatedInput + estimatedOutput)
                                }
                            }
                        case .failure(let error):
                            collected[name] = "最终论述生成失败：\(error.localizedDescription)"
                        }
                        completedCount += 1
                        secretaryCollectCompleted = completedCount

                        if let ai = aiOrder.first(where: { Config.shared.participants[$0.index].name == name }),
                           let pIdx = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[pIdx].status = .present
                        }
                    }
                }
            }

            await MainActor.run {
                finalStatements = collected
                secretaryPhase = .summarizing

                currentSpeaker = "秘书正在汇总…"

                let userMessages = self.messages.filter { $0.isUser }.map { $0.content }.joined(separator: "\n\n")
                let aiSections = collected.map { "### \($0.key)\n\n\($0.value)" }.joined(separator: "\n\n---\n\n")
                let combinedText = "## 用户发言\n\n\(userMessages)\n\n---\n\n\(aiSections)"
                let secretaryMessages: [[String: String]] = [
                    ["role": "system", "content": secretarySystemPrompt],
                    ["role": "user", "content": "以下是本轮会议用户发言及各参会AI的最终论述：\n\n\(combinedText)"]
                ]

                APIService.callAI(config: Config.shared.secretary, messages: secretaryMessages, enableThinking: false) { result in
                    DispatchQueue.main.async {
                        messages.removeAll { $0.id == progressID }
                        currentProgressMessageID = nil
                        secretaryStartTime = nil

                        switch result {
                        case .success(let (content, usage)):
                            secretaryBaseContent = content
                            let fullContent = self.buildSecretaryDisplayContent()
                            let secretaryMsg = Message(sender: "秘书", content: fullContent, isUser: false)
                            messages.append(secretaryMsg)
                            secretaryMessageID = secretaryMsg.id

                        case .failure(let error):
                            let fallbackText = aiOrder.map { ai in
                                let name = Config.shared.participants[ai.index].name
                                guard let text = collected[name] else { return "### \(name)\n\n(无内容)" }
                                return "### \(name)\n\n\(text)"
                            }.joined(separator: "\n\n---\n\n")
                            secretaryBaseContent = "# 秘书汇总失败\n\n\(error.localizedDescription)\n\n---\n\n# 参会方论述汇总：\n\n\(fallbackText)"
                            let fullContent = self.buildSecretaryDisplayContent()
                            let secretaryMsg = Message(sender: "秘书", content: fullContent, isUser: false)
                            messages.append(secretaryMsg)
                            secretaryMessageID = secretaryMsg.id

                            let retryMsg = Message(sender: "系统", content: "秘书汇总因网络或超时失败，已自动回退为原始论述展示。\n点击下方按钮重试：  \n[🔄 重试汇总](nm://retry-summary)", isUser: false)
                            messages.append(retryMsg)
                        }

                        secretaryPhase = .done
                        currentSpeaker = ""
                        isStreaming = false
                    }
                }
            }
        }
    }

    // MARK: - Token 统计

    @State var totalInputTokens: Int = 0
    @State var totalOutputTokens: Int = 0

    // MARK: - 秘书展示构造

    func buildSecretaryDisplayContent() -> String {
        var content = secretaryBaseContent

        if !userSupplement.isEmpty {
            content += "\n\n---\n\n**用户补充意见：**\n\n\(userSupplement)"
        }

        content += "\n\n---\n\n亲爱的nomo，您还需要补充其他意见吗？"
        return content
    }

    // MARK: - 补充意见

    func submitSupplement() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard secretaryPhase == .done else { return }

        userSupplement = text
        inputText = ""

        if let msgID = secretaryMessageID,
           let idx = messages.firstIndex(where: { $0.id == msgID }) {
            messages[idx].content = buildSecretaryDisplayContent()
        }
    }

    // MARK: - 提交最终论述

    func submitFinalStatements() {
        guard secretaryPhase == .done else { return }

        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }

        var anonymousText = secretaryBaseContent
        let splitMarkers = ["## 分歧点总结", "### 分歧点总结", "# 分歧点总结"]
        for marker in splitMarkers {
            if let splitRange = anonymousText.range(of: marker) {
                anonymousText = String(anonymousText[..<splitRange.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }

        let aiNames = presentAIs.map { Config.shared.participants[$0.index].name }
        let labels = ["观点A", "观点B", "观点C"]
        for (i, name) in aiNames.enumerated() {
            guard i < labels.count else { break }
            anonymousText = anonymousText.replacingOccurrences(of: name, with: labels[i])
        }

        var submissionText = anonymousText
        if !userSupplement.isEmpty {
            submissionText += "\n\n---\n\n# 用户补充意见\n\n\(userSupplement)"
        }

        for ai in presentAIs {
            let name = Config.shared.participants[ai.index].name
            aiMessageHistories[name] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": submissionText]
            ]
        }

        userSupplement = ""
        secretaryPhase = .idle
        secretaryBaseContent = ""
        secretaryMessageID = nil
        finalStatements = [:]

        let userName = Config.shared.userName.isEmpty ? "我" : Config.shared.userName
        messages.append(Message(sender: "系统", content: "✅ 最终论述已提交，各参会 AI 已获悉本轮讨论结论。您可以发起新一轮讨论。", isUser: false))
    }

    // MARK: - 重试秘书汇总

    func handleRetrySummary() {
        guard !pendingAIOrder.isEmpty, secretaryPhase == .done else { return }

        secretaryPhase = .idle
        messages.append(Message(sender: "系统", content: "🔄 正在重试秘书汇总…", isUser: false))
        triggerFinalStatements(for: pendingAIOrder)
    }
}

