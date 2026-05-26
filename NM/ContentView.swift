import SwiftUI
import Combine
import AppKit
import MarkdownUI
import UniformTypeIdentifiers

// MARK: - 消息模型

enum SystemBubbleType {
    case lightBlue
    case yellow
}

struct Message: Identifiable, Equatable {
    let id = UUID()
    let sender: String
    var content: String
    let isUser: Bool
    var timerSuffix: String? = nil
    var systemBubbleType: SystemBubbleType = .lightBlue // 默认浅蓝色
}

struct UploadedFileInfo: Identifiable, Codable {
    var id = UUID()
    let fileName: String
    let uploadTime: Date
}

// MARK: - Token 缓冲器

class TokenBuffer {
    private var reasoningBuffer = ""
    private var contentBuffer = ""
    private var lastReasoningFlush = Date()
    private var lastContentFlush = Date()

    private var flushInterval: TimeInterval {
        let totalLen = reasoningBuffer.count + contentBuffer.count
        if totalLen < 500  { return 0.15 }
        if totalLen < 2000 { return 0.3 }
        return 0.5
    }

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

// MARK: - 输入框状态管理

class TextEditorState: ObservableObject {
    @Published var text: String = ""
    weak var coordinator: TextEditorCoordinator?
    
    func insertTextAtCursor(_ text: String) {
        coordinator?.insertTextAtCursor(text)
    }
    
    func clear() {
        coordinator?.clear()
    }
}

protocol TextEditorCoordinator: AnyObject {
    func insertTextAtCursor(_ text: String)
    func clear()
}

// MARK: - 自适应高度输入框

struct GrowingTextEditor: NSViewRepresentable {
    @ObservedObject var state: TextEditorState
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, onSubmit: onSubmit)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = NSTextView()
        context.coordinator.setTextView(textView)
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
        // 不再反向同步，避免破坏 IME 组合状态
    }

    class Coordinator: NSObject, NSTextViewDelegate, TextEditorCoordinator {
        private weak var state: TextEditorState?
        private weak var textView: NSTextView?
        private let onSubmit: () -> Void

        init(state: TextEditorState, onSubmit: @escaping () -> Void) {
            self.state = state
            self.onSubmit = onSubmit
            super.init()
            state.coordinator = self
        }
        
        func setTextView(_ view: NSTextView) {
            self.textView = view
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            Task { @MainActor in
                self.state?.text = textView.string
            }
        }
        
        func insertTextAtCursor(_ text: String) {
            guard let textView = textView else { return }
            let currentText = textView.string
            let newText = currentText.isEmpty ? text : "\(currentText) \(text)"
            textView.string = newText
            self.state?.text = newText
        }
        
        func clear() {
            textView?.string = ""
            state?.text = ""
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                if flags.contains(.shift) {
                    textView.insertText("\n", replacementRange: textView.selectedRange())
                    return true
                } else {
                    state?.text = textView.string
                    onSubmit()
                    return true
                }
            }
            return false
        }
    }
}

// MARK: - 主视图

struct ContentView: View {
    // ──────────────── 基础状态 ────────────────
    @EnvironmentObject var localization: LocalizationManager
    @State var messages: [Message] = []
    @StateObject private var editorState = TextEditorState()
    @State var currentSpeaker: String = ""
    @State var isStreaming = false
    @State var currentStreamMessageID: UUID? = nil
    @State var currentRound = 1

    // ──────────────── 参会者 ────────────────
    @State var participants: [Participant] = (0..<Config.shared.participants.count).map {
        Participant(index: $0)
    }

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
    @State var summaryTimer: Timer? = nil

    // ──────────────── 设置面板 ────────────────
    @State var showSettings = false

    @State var showNewMeeting = false
    @State var showHistory = false
    @State var showHelp = false
    @State var showFlowchart = false
    @State var isEndingMeeting = false
    @State var currentMeetingTopic: String? = nil
    @State var meetingStartTime: Date? = nil
    @State var meetingDirURL: URL? = nil
    @State var meetingDirBookmark: Data? = nil
    @State var inputLocked = false
    
    enum TopMessageType {
        case red
        case darkGreen
    }
    
    @State private var topMessage: (text: String, type: TopMessageType)? = nil
    @State private var topMessageTimer: Timer? = nil
    @State private var disappearingText: String? = nil
    @State private var disappearingTimer: Timer? = nil
    @State private var originalErrorText: String? = nil
    @State private var summaryInProgress: Bool = false
    // 悄悄问秘书相关状态
    @State private var showWhisperWindow = false
    @State private var whisperInput = ""
    @State private var whisperMessages: [(isUser: Bool, content: String)] = []
    @State private var whisperWindowOffset: CGSize = .zero
    @State private var isWhisperLoading = false
    @State private var whisperHistoryIndex = -1
    @FocusState private var isWhisperInputFocused: Bool
    @State private var lastSavedRound: Int = 0
    @State private var lastSavedMessageCount: Int = 0
    @State private var needsScrollToBottom: Bool = false
    @State private var ragProcessingInProgress: Bool = false
    @State private var currentRAGProcessingMsgID: UUID? = nil
    @State private var uploadedFiles: [UploadedFileInfo] = []
    @State private var autoSaveTimer: Timer? = nil
    @State private var meetingDuration: TimeInterval = 0
    @State private var meetingDurationTimer: Timer? = nil

    // ──────────────── 常量 ────────────────
    var systemPrompt: String { localization.systemPrompt }
    var secretarySystemPrompt: String { localization.secretarySystemPrompt }
    var finalStatementPrompt: String { localization.finalStatementPrompt }
    var summarizationPrompt: String { localization.summarizationPrompt }

    // ──────────────── 计算属性 ────────────────
    /// 该参会 AI 是否已配置（name 和 apiKey 均非空）
    func isConfigured(_ p: Participant) -> Bool {
        let cfg = Config.shared.participants[p.index]
        return !cfg.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // ──────────────── 视图 ────────────────
    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if showSettings {
                    SettingsView(dismissAction: { showSettings = false })
                } else if showNewMeeting {
                NewMeetingView(
                    onCancel: { showNewMeeting = false },
                    onCreate: { topic, startTime, selectedFiles in
                        do {
                            let session = try MeetingManager.createMeeting(topic: topic)
                            currentMeetingTopic = topic
                            meetingStartTime = startTime
                            meetingDirURL = session.dirURL
                            meetingDirBookmark = session.dirBookmark
                            meetingDuration = 0
                            meetingDurationTimer?.invalidate()
                            meetingDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                                meetingDuration += 1
                            }
                            inputLocked = false
                            showNewMeeting = false
                            messages.removeAll()
                            currentRound = 1
                            aiMessageHistories.removeAll()
                            finalStatements.removeAll()
                            secretaryPhase = .idle
                            secretaryBaseContent = ""
                            secretaryMessageID = nil
                            userSupplement = ""
                            currentSpeaker = ""
                            isStreaming = false
                            topMessage = nil
                            lastSavedRound = 0
                            lastSavedMessageCount = 0
                            uploadedFiles = []
                            ragProcessingInProgress = false
                            currentRAGProcessingMsgID = nil
                            
                            startAutoSaveTimer()
                            saveMeetingStateToDisk()
                            saveMeetingConfigSnapshotToDisk()
                            
                            // 异步复制上传的文件到uploads目录
                            if !selectedFiles.isEmpty {
                                let bookmark = session.dirBookmark
                                DispatchQueue.global(qos: .background).async {
                                    guard let (resolved, isStale) = try? URL.from(securityBookmark: bookmark),
                                          !isStale,
                                          resolved.startAccessingSecurityScopedResource() else {
                                        DispatchQueue.main.async {
                                            self.addSystemMessageWithTop(localization.storageAccessFailed, topType: .red, bubbleType: .yellow)
                                        }
                                        return
                                    }
                                    defer { resolved.stopAccessingSecurityScopedResource() }

                                    let uploadsDir = resolved.appendingPathComponent("uploads", isDirectory: true)
                                    try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

                                    var successCount = 0
                                    var failCount = 0
                                    for fileURL in selectedFiles {
                                        let fileName = fileURL.lastPathComponent
                                        var targetURL = uploadsDir.appendingPathComponent(fileName)
                                        var fileIndex = 1
                                        while FileManager.default.fileExists(atPath: targetURL.path) {
                                            let nameWithoutExt = (fileName as NSString).deletingPathExtension
                                            let ext = (fileName as NSString).pathExtension
                                            targetURL = uploadsDir.appendingPathComponent("\(nameWithoutExt)(\(fileIndex)).\(ext)")
                                            fileIndex += 1
                                        }
                                        do {
                                            try FileManager.default.copyItem(at: fileURL, to: targetURL)
                                            successCount += 1
                                        } catch { failCount += 1 }
                                    }

                                    if successCount == 0 && failCount == 0 {
                                        return
                                    }

                                    if successCount > 0 || failCount > 0 {
                                        DispatchQueue.main.async {
                                            // 构建初始内容
                                            var content = ""
                                            if successCount > 0 { content += localization.filesUploaded(successCount) }
                                            if failCount > 0 { content += "\n\(localization.filesUploadFailed(failCount))" }
                                            
                                            // 纯失败无需构建索引，直接显示
                                            guard successCount > 0 else {
                                                self.addSystemMessageWithTop(content, topType: .red, bubbleType: .yellow)
                                                return
                                            }
                                            
                                            // 有成功文件，创建RAG专属动态气泡
                                            content += "\n\(localization.buildingIndexProgress)"
                                            var ragMsg = Message(sender: localization.systemSender, content: content, isUser: false)
                                            ragMsg.systemBubbleType = failCount > 0 ? .yellow : .lightBlue
                                            self.messages.append(ragMsg)
                                            self.currentRAGProcessingMsgID = ragMsg.id
                                            self.ragProcessingInProgress = true
                                            self.needsScrollToBottom = true
                                            
                                            for fileURL in selectedFiles {
                                                self.uploadedFiles.append(UploadedFileInfo(fileName: fileURL.lastPathComponent, uploadTime: Date()))
                                            }
                                            
                                            self.saveMeetingStateToDisk()
                                            
                                            // 异步构建索引
                                            Task {
                                                let dbURL = resolved
                                                do {
                                                    try await RAGService.buildIndex(meetingDir: dbURL)
                                                    DispatchQueue.main.async {
                                                        if let msgID = self.currentRAGProcessingMsgID, let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
                                                            var msg = self.messages[idx]
                                                            let baseContent = msg.content.components(separatedBy: "\n⏳").first ?? msg.content
                                                            msg.content = baseContent + "\n\(localization.indexBuildComplete)"
                                                            msg.systemBubbleType = failCount > 0 ? .yellow : .lightBlue
                                                            self.messages[idx] = msg
                                                            self.showTopMessage(localization.indexBuildComplete, type: .darkGreen)
                                                        }
                                                        self.ragProcessingInProgress = false
                                                        self.currentRAGProcessingMsgID = nil
                                                    }
                                                } catch {
                                                    DispatchQueue.main.async {
                                                        if let msgID = self.currentRAGProcessingMsgID, let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
                                                            var msg = self.messages[idx]
                                                            let baseContent = msg.content.components(separatedBy: "\n⏳").first ?? msg.content
                                                            msg.content = baseContent + "\n\(localization.indexBuildFailed(error.localizedDescription))"
                                                            msg.systemBubbleType = .yellow
                                                            self.messages[idx] = msg
                                                            self.showTopMessage(localization.indexBuildFailed(error.localizedDescription), type: .red)
                                                        }
                                                        self.ragProcessingInProgress = false
                                                        self.currentRAGProcessingMsgID = nil
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        } catch {
                            showTopMessage(localization.createMeetingFailed(error.localizedDescription), type: .red)
                        }
                    }
                )
                } else {
                    HStack(spacing: 0) {
                        // 左侧面板：参会列表
                        sidebarView
                            .frame(width: 280)
                            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                        Divider()

                        // 右侧：聊天 + 输入
                        VStack(spacing: 0) {
                            chatView
                            inputView
                        }
                    }
                }
            }
            }
            
            // 悄悄问秘书浮动窗口
            if showWhisperWindow {
                VStack(spacing: 0) {
                    // 标题栏 - 可拖拽
                    HStack {
                        Text(localization.whisperWindowTitle)
                            .font(.headline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: {
                            showWhisperWindow = false
                            isWhisperInputFocused = false
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.title2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                whisperWindowOffset = CGSize(
                                    width: whisperWindowOffset.width + value.translation.width,
                                    height: whisperWindowOffset.height + value.translation.height
                                )
                            }
                    )
                    
                    // 消息列表
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 8) {
                                ForEach(0..<whisperMessages.count, id: \.self) { index in
                                    let msg = whisperMessages[index]
                                    Text(msg.content)
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(msg.isUser ? Color(red: 0.93, green: 0.36, blue: 0.46).opacity(0.15) : Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.1))
                                        .cornerRadius(6)
                                        .foregroundColor(msg.isUser ? Color(red: 0.8, green: 0.2, blue: 0.2) : Color(red: 0.6, green: 0.3, blue: 0.8))
                                        .id(index)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                        .onChange(of: whisperMessages.count) { _, _ in
                            guard !whisperMessages.isEmpty else { return }
                            proxy.scrollTo(whisperMessages.count - 1, anchor: .bottom)
                        }
                    }
                    
                    Divider()
                    
                    // 底部输入框
                    HStack(spacing: 8) {
                        TextField(localization.whisperInputPlaceholder, text: $whisperInput, axis: .vertical)
                            .textFieldStyle(.plain)
                            .lineLimit(3)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                            .focused($isWhisperInputFocused)
                            .disabled(isWhisperLoading)
                            .onKeyPress(.upArrow) {
                                guard !whisperMessages.isEmpty else { return .ignored }
                                let userMessages = whisperMessages.enumerated().filter { $0.element.isUser }.map { $0.element.content }
                                guard !userMessages.isEmpty else { return .ignored }
                                whisperHistoryIndex = min(whisperHistoryIndex + 1, userMessages.count - 1)
                                whisperInput = userMessages[userMessages.count - 1 - whisperHistoryIndex]
                                return .handled
                            }
                            .onKeyPress(.downArrow) {
                                guard whisperHistoryIndex >= 0 else { return .ignored }
                                whisperHistoryIndex -= 1
                                if whisperHistoryIndex >= 0 {
                                    let userMessages = whisperMessages.enumerated().filter { $0.element.isUser }.map { $0.element.content }
                                    whisperInput = userMessages[userMessages.count - 1 - whisperHistoryIndex]
                                } else {
                                    whisperInput = ""
                                }
                                return .handled
                            }
                            .onKeyPress(.escape) {
                                showWhisperWindow = false
                                isWhisperInputFocused = false
                                return .handled
                            }
                            .onSubmit {
                                sendWhisperMessage()
                            }
                        
                        Button(action: sendWhisperMessage) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(isWhisperLoading ? .secondary : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(isWhisperLoading || whisperInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(width: 450, height: 500)
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
                .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 5)
                .offset(whisperWindowOffset)
                .transition(.opacity.combined(with: .scale))
                .animation(.easeInOut(duration: 0.2), value: showWhisperWindow)
            }
        }
        .sheet(isPresented: $showHistory) {
            HistoryListView(
                onDismiss: { showHistory = false },
                onResume: { meeting in
                    showHistory = false
                    resumeMeeting(meeting)
                }
            )
        }
        .sheet(isPresented: $showHelp) {
            HelpView()
                .environmentObject(localization)
        }
        .sheet(isPresented: $showFlowchart) {
            FlowchartView()
                .environmentObject(localization)
        }
        .onAppear {
            // 启动时检查存储路径是否已配置，未配置则自动打开设置界面
            if Config.shared.customStorageBookmark == nil {
                showSettings = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showSettings)) { _ in
            showSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .showHelp)) { _ in
            showHelp = true
        }
        .frame(minWidth: 1000, minHeight: 700)
        .preferredColorScheme(.light)
        .onChange(of: currentMeetingTopic) { _, _ in
            // 切换会议/结束会议清空悄悄问记录
            whisperMessages.removeAll()
            showWhisperWindow = false
        }
    }

    // MARK: - 侧边栏

    private var fileRowsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(uploadedFiles.enumerated()), id: \.element.id) { idx, file in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(idx + 1). \(file.fileName)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(file.fileName)
                    Text(formatUploadTime(file.uploadTime))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    editorState.insertTextAtCursor("「\(file.fileName)」")
                }
                
                if idx < uploadedFiles.count - 1 {
                    Divider().padding(.horizontal, 8)
                }
            }
        }
    }

    var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(localization.participantsSection)
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // 用户
                    sidebarUserRow()

                    // 参会 AI
                    ForEach(participants) { p in
                        sidebarParticipantRow(p)
                    }

                    // 秘书
                    sidebarSecretaryRow()
                }
            }

            // 查看会议流程（小链接）
            Button(action: { showFlowchart = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "flowchart")
                        .font(.caption2)
                    Text("会议流程")
                        .font(.caption2)
                }
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if !uploadedFiles.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(localization.uploadedDocuments)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    Text(localization.clickDocumentToQuoteHint)
                .font(.footnote)
                .foregroundColor(.blue)
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(4)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
                    
                    Group {
                        if uploadedFiles.count > 10 {
                            ScrollView {
                                fileRowsView
                            }
                            .frame(maxHeight: 300)
                        } else {
                            fileRowsView
                        }
                    }
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.2), lineWidth: 1))
                    .padding(.horizontal, 16)
                }
            }

            Spacer()
            
            // 会议控制按钮：新建/结束/历史
            HStack(spacing: 12) {
                Spacer()
                if currentMeetingTopic == nil {
                    statusCapsuleButton(
                        icon: "clock.arrow.circlepath",
                        label: localization.historyMeetingButton,
                        bgColor: Color.gray.opacity(0.12),
                        borderColor: Color.gray.opacity(0.3),
                        textColor: .gray,
                        width: 100
                    ) {
                        showHistory = true
                    }
                    
                    statusCapsuleButton(
                        icon: "plus.circle.fill",
                        label: localization.newMeetingButton,
                        bgColor: Color.blue.opacity(0.12),
                        borderColor: Color.blue.opacity(0.3),
                        textColor: .blue,
                        width: 100
                    ) {
                        showNewMeeting = true
                    }
                } else {
                    statusCapsuleButton(
                        icon: "xmark.circle.fill",
                        label: localization.endMeetingButton,
                        bgColor: Color.red.opacity(0.12),
                        borderColor: Color.red.opacity(0.3),
                        textColor: .red,
                        width: 100
                    ) {
                        endMeeting()
                    }
                }
                Spacer()
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - 颜色工具

    func avatarColor(for role: String) -> Color {
        switch role {
        case "user":      return .red
        case "ai":        return .blue
        case "secretary": return .green
        default:          return .gray
        }
    }

    func formatTokens(_ tokens: Int) -> String {
        if tokens < 1000 {
            return "\(tokens)"
        } else if tokens < 1_000_000 {
            return String(format: "%.1fK", Double(tokens) / 1000.0)
        } else {
            return String(format: "%.1fM", Double(tokens) / 1_000_000.0)
        }
    }

    func formatUploadTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd HH:mm"
        return f.string(from: date)
    }

    // MARK: - 统一胶囊按钮

    @ViewBuilder
    func statusCapsuleButton(
        icon: String? = nil,
        label: String,
        bgColor: Color,
        borderColor: Color,
        textColor: Color,
        dotColor: Color? = nil,
        width: CGFloat = 72,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption2)
                }
                if let dotColor = dotColor {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 6, height: 6)
                }
                Text(label)
                    .font(.caption2)
                    .foregroundColor(textColor)
            }
            .frame(width: width, height: 22)
            .background(Capsule().fill(bgColor))
            .overlay(Capsule().stroke(borderColor, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 侧边栏行

    func sidebarUserRow() -> some View {
        HStack {
            Text(Config.shared.userName.isEmpty ? (localization.isChinese ? "我" : "Me") : Config.shared.userName)
                .font(.body)
                .foregroundColor(Color(red: 0.8, green: 0.2, blue: 0.2))

            Spacer()

            statusCapsuleButton(
                icon: "gearshape",
                label: localization.settingsSidebarButton,
                bgColor: Color.white.opacity(0.9),
                borderColor: Color.gray.opacity(0.2),
                textColor: .secondary
            ) {
                showSettings = true
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 42)
        .padding(.horizontal, 16)
    }

    func sidebarParticipantRow(_ p: Participant) -> some View {
        let cfg = Config.shared.participants[p.index]
        let configured = isConfigured(p)
        let isActive = configured && p.status != .away

        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(configured ? cfg.name : (localization.isChinese ? "空" : "Empty"))
                    .font(.body)
                    .foregroundColor(isActive ? Color(red: 0.2, green: 0.4, blue: 0.8) : .secondary)
                Text(configured ? cfg.model : localization.notConfigured)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(alignment: .bottom, spacing: 4) {
                Text(formatTokens(p.accumulatedTokens))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)

                if configured {
                    let isAway = p.status == .away
                    statusCapsuleButton(
                        label: statusLabel(p.status),
                        bgColor: isAway ? Color.white.opacity(0.9) : getStatusColor(p.status).opacity(0.15),
                        borderColor: isAway ? Color.gray.opacity(0.2) : getStatusColor(p.status).opacity(0.5),
                        textColor: .secondary
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            toggleParticipantStatus(p)
                        }
                    }
                } else {
                    statusCapsuleButton(
                        label: localization.notAttending,
                        bgColor: Color.white.opacity(0.9),
                        borderColor: Color.gray.opacity(0.2),
                        textColor: .secondary
                    ) {
                        showSettings = true
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 42)
        .padding(.horizontal, 16)
    }

    func sidebarSecretaryRow() -> some View {
        let secCfg = Config.shared.secretary
        let secConfigured = !secCfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isIdle = secretaryPhase == .idle

        return HStack {
            Text(localization.secretaryLabel)
                .font(.body)
                .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))

            Spacer()

            HStack(alignment: .center, spacing: 4) {
                if totalInputTokens + totalOutputTokens > 0 {
                    Text(formatTokens(totalInputTokens + totalOutputTokens))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(minWidth: 36, alignment: .trailing)
                }
                
                // 悄悄问秘书按钮
                 Button(action: {
                     guard secretaryPhase == .idle && !summaryInProgress && !isEndingMeeting else {
                         showTopMessage(localization.secretaryBusyTip, type: .red)
                         return
                     }
                     showWhisperWindow = true
                     whisperHistoryIndex = -1
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         isWhisperInputFocused = true
                     }
                 }) {
                     Text("W")
                         .font(.caption.bold())
                         .foregroundColor(Color(red: 0.6, green: 0.3, blue: 0.8))
                         .frame(width: 20, height: 20)
                         .background(Color.white.opacity(0.9))
                         .cornerRadius(10)
                         .overlay(
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.5), lineWidth: 1)
                         )
                 }
                 .buttonStyle(.plain)
                 .disabled(secretaryPhase != .idle || summaryInProgress || isEndingMeeting)

                statusCapsuleButton(
                    label: (!isIdle && !isEndingMeeting) ? localization.consolidatingButton : localization.consolidateButton,
                    bgColor: (!isIdle && !isEndingMeeting) ? Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.15) : Color.white.opacity(0.9),
                    borderColor: (!isIdle && !isEndingMeeting) ? Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.5) : Color.gray.opacity(0.2),
                    textColor: .secondary
                ) {
                    if isIdle && secConfigured {
                        if lastSavedRound == currentRound && messages.count == lastSavedMessageCount {
                            reuseSummaryAsSummaryResult()
                        } else {
                            triggerSummary()
                        }
                    } else if !secConfigured {
                        showSettings = true
                    }
                }
                
                statusCapsuleButton(
                    label: summaryInProgress ? localization.summarizingButton : localization.summarizeButton,
                    bgColor: summaryInProgress ? Color.orange.opacity(0.15) : Color.white.opacity(0.9),
                    borderColor: summaryInProgress ? Color.orange.opacity(0.5) : Color.gray.opacity(0.2),
                    textColor: .secondary
                ) {
                    if isIdle && secConfigured && !summaryInProgress {
                        // 先做全场景校验
                        guard !hasSpeakingAI() else {
                            showTopMessage(localization.waitAllSpeakersBeforeSummary, type: .red)
                            return
                        }
                        guard !(secretaryPhase != .idle) else {
                            showTopMessage(localization.secretaryConsolidatingNoSummary, type: .red)
                            return
                        }
                        guard !(lastSavedRound == currentRound && messages.count == lastSavedMessageCount) else {
                            showTopMessage(localization.summaryDoneUseConsolidate, type: .red)
                            return
                        }
                        // 执行总结流程
                        triggerOnlySummary()
                    } else if !secConfigured {
                        showSettings = true
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 42)
        .padding(.horizontal, 16)
    }

    // MARK: - 状态辅助方法

    func statusLabel(_ status: AIStatus) -> String {
        switch status {
        case .away:     return localization.statusAway
        case .present:  return localization.statusPresent
        case .thinking: return localization.statusThinking
        case .speaking: return localization.statusSpeaking
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
    
    // MARK: - 辅助校验方法
    func hasSpeakingAI() -> Bool {
        for p in participants {
            if p.status == .thinking || p.status == .speaking {
                return true
            }
        }
        return false
    }
    
    // MARK: - 复制当前轮对话
    func copyCurrentRound() {
        // 检查是否有AI正在处理
        if isStreaming || hasSpeakingAI() || secretaryPhase != .idle || summaryInProgress {
            showTopMessage(localization.aiProcessingWait, type: .red)
            return
        }
        
        // 拼接对话内容
        var content = ""
        for msg in messages {
            if msg.sender == localization.systemSender {
                continue // 跳过系统消息
            } else if msg.isUser {
                content += localization.userSpoke(msg.content)
            } else if msg.sender.hasSuffix(localization.thinkingSuffix) {
                let name = String(msg.sender.dropLast(localization.thinkingSuffix.count))
                content += localization.aiThought(name, msg.content)
            } else if msg.sender == localization.secretaryLabel {
                content += localization.secretarySpoke(msg.content)
            } else {
                content += localization.aiSpoke(msg.sender, msg.content)
            }
        }
        
        // 写入剪贴板
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        
        // 成功提示
        showTopMessage(localization.copiedToClipboard, type: .darkGreen)
    }
    
    func hasUnsavedContent() -> Bool {
        guard lastSavedRound > 0 else { return true }
        if lastSavedRound != currentRound { return true }
        return messages.count > lastSavedMessageCount
    }
    
    func formatMeetingDuration() -> String {
        let totalSeconds = Int(meetingDuration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    // MARK: - 总结逻辑
    func triggerOnlySummary() {
        summaryInProgress = true
        
        // 校验是否有正在进行的会议
        guard currentMeetingTopic != nil else {
            summaryInProgress = false
            addSystemMessage(localization.pleaseCreateMeeting, bubbleType: .yellow)
            return
        }
        
        // 获取当前参会AI
        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            summaryInProgress = false
            addSystemMessage(localization.noAIToSummarize, bubbleType: .yellow)
            return
        }

        let hasHistory = presentAIs.contains { ai in
            let cfg = Config.shared.participants[ai.index]
            guard let history = aiMessageHistories[cfg.name] else { return false }
            return history.contains { $0["role"] == "user" }
        }
        guard hasHistory else {
            summaryInProgress = false
            addSystemMessage(localization.noHistoryToSummarize, bubbleType: .yellow)
            return
        }

        // 复用汇总收集逻辑，完成后直接保存不进入提交状态
        triggerFinalStatementsInternal(for: presentAIs) { [self] summaryContent in
            self.summaryInProgress = false
            
            // 保存总结内容到轮次记录
            if let meetingDir = self.meetingDirURL {
                do {
                    try MeetingArchiveService.saveRound(round: self.currentRound, summary: summaryContent, supplement: "", meetingDir: meetingDir, showUserSupplement: false)
                self.lastSavedRound = self.currentRound
                self.messages.append(Message(sender: localization.secretaryLabel, content: summaryContent, isUser: false))
                self.addSystemMessageWithTop(localization.roundSummarySaved, topType: .darkGreen, bubbleType: .lightBlue)
                self.saveNewMessagesToDisk()
                } catch {
                    self.addSystemMessageWithTop(localization.summarySaveFailed(error.localizedDescription), topType: .red, bubbleType: .yellow)
                }
            }
            // 重置秘书状态，恢复按钮可用性
            self.secretaryPhase = .idle
            self.isStreaming = false
            self.currentSpeaker = ""
            self.pendingAIOrder = []
            self.finalStatements = [:]
        }
    }
    
    // MARK: - 复用总结内容为汇总结果
    func reuseSummaryAsSummaryResult() {
        // 读取最新一轮的总结文件内容
        if let meetingDir = meetingDirURL {
            let roundFile = MeetingManager.roundFilePath(meetingDir: meetingDir, round: currentRound)
            if let content = try? String(contentsOf: roundFile, encoding: .utf8) {
                // 提取汇总部分（去掉头部和用户补充）
                secretaryBaseContent = content
                secretaryPhase = .done
                // 展示汇总内容，统一调用buildSecretaryDisplayContent加上末尾提问
                let secretaryMsg = Message(sender: localization.secretaryLabel, content: buildSecretaryDisplayContent(), isUser: false)
                messages.append(secretaryMsg)
                secretaryMessageID = secretaryMsg.id // 记录消息ID，用于后续补充意见更新界面
            }
        }
    }

    func toggleParticipantStatus(_ p: Participant) {
        guard currentMeetingTopic != nil else {
            addSystemMessage(localization.pleaseCreateMeeting, bubbleType: .yellow)
            return
        }
        // 校验该AI是否完成配置
        guard isConfigured(p) else {
            addSystemMessage(localization.aiNotConfigured, bubbleType: .yellow)
            return
        }
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
        VStack(spacing: 0) {
            HStack {
                Text(currentMeetingTopic ?? "")
                    .font(.headline)
                Text(localization.roundLabel(currentRound))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button(action: copyCurrentRound) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help(localization.copyCurrentRoundHelp)
                Text(formatMeetingDuration())
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if let (text, type) = topMessage {
                    Text(disappearingText ?? text)
                        .font(.system(size: 12))
                        .foregroundColor(type == .red ? .red : Color(red: 0.2, green: 0.6, blue: 0.2))
                        .lineLimit(1)
                        .onAppear {
                            originalErrorText = text
                            disappearingText = nil
                            topMessageTimer?.invalidate()
                            topMessageTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { _ in
                                startDisappearing()
                            }
                        }
                        .onDisappear {
                            topMessageTimer?.invalidate()
                            disappearingTimer?.invalidate()
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messages) { msg in
                            MessageBubble(
                                msg: msg,
                                allMessages: messages,
                                onRetry: {
                                    handleRetrySummary()
                                }, onEndSummarize: {
                                    handleEndSummarize()
                                }, onEndForce: {
                                    handleEndForce()
                                }
                            )
                            .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: needsScrollToBottom) { oldValue, newValue in
                    if newValue {
                        scrollToBottom(proxy: proxy)
                        needsScrollToBottom = false
                    }
                }
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
        let allMessages: [Message]
        let onRetry: () -> Void
        let onEndSummarize: () -> Void
        let onEndForce: () -> Void
        @State private var copied = false
        @EnvironmentObject var localization: LocalizationManager

        private var title: String {
            if msg.sender == localization.secretaryLabel { return localization.secretaryDisplayDefault }
            if msg.sender.hasSuffix(localization.thinkingSuffix) { return localization.thinkingBubble }
            return localization.speakingBubble
        }
        
        private var showName: Bool {
            guard let index = allMessages.firstIndex(where: { $0.id == msg.id }) else {
                return true
            }
            if index == 0 {
                return true
            }
            let previousMsg = allMessages[index - 1]
            let currentDisplayName = msg.sender.hasSuffix(localization.thinkingSuffix) ? String(msg.sender.dropLast(localization.thinkingSuffix.count)) : msg.sender
            let previousDisplayName = previousMsg.sender.hasSuffix(localization.thinkingSuffix) ? String(previousMsg.sender.dropLast(localization.thinkingSuffix.count)) : previousMsg.sender
            return currentDisplayName != previousDisplayName
        }

        var body: some View {
            if msg.sender == localization.systemSender {
                // 系统消息：左右边距和外层容器一致（16点）
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        systemBubble
                    }
                }
            } else {
                // 普通消息：保持原有布局
                HStack(alignment: .top) {
                    if msg.isUser {
                        Spacer(minLength: 60)
                    }

                    VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
                        // 名字在气泡外
                        if showName {
                            let displayName = msg.sender.hasSuffix(localization.thinkingSuffix)
                                ? String(msg.sender.dropLast(localization.thinkingSuffix.count))
                                : msg.sender
                            Text(displayName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(
                                    msg.isUser ? Color(red: 0.8, green: 0.2, blue: 0.2) :
                                    msg.sender == localization.secretaryLabel ? Color(red: 0.6, green: 0.3, blue: 0.8) :
                                    Color(red: 0.2, green: 0.4, blue: 0.8)
                                )
                                .padding(.horizontal, 4)
                        }
                        contentBubble
                    }

                    if !msg.isUser {
                        Spacer(minLength: 60)
                    }
                }
            }
        }

        // MARK: - 系统消息（蓝色气泡）

        var systemBubble: some View {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "hand.raised")
                    .foregroundColor(Color(red: 0.05, green: 0.15, blue: 0.55).opacity(0.95))
                    .font(.callout)
                
                if msg.content.contains("nm://") {
                    parsedSystemMessage
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(msg.content)
                            .foregroundColor(Color(red: 0.05, green: 0.15, blue: 0.55).opacity(0.95))
                            .textSelection(.enabled)
                        if let suffix = msg.timerSuffix {
                            Text(suffix)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }
                
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(msg.systemBubbleType == .lightBlue ? Color.blue.opacity(0.08) : Color.yellow.opacity(0.15))
            .cornerRadius(10)
            .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
            .frame(maxWidth: .infinity)
        }

        // MARK: - 解析含 nm:// 链接的系统消息

        var parsedSystemMessage: some View {
            let cleaned = stripNMURLs(from: msg.content)
            let actions = extractNMActions()
            return VStack(alignment: .leading, spacing: 8) {
                if !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Markdown(cleaned)
                        .markdownTheme(.meeting)
                        .textSelection(.enabled)
                        .foregroundColor(Color(red: 0.05, green: 0.15, blue: 0.55).opacity(0.95))
                }
                if !actions.isEmpty {
                    HStack(spacing: 12) {
                        ForEach(actions, id: \.0) { host, label in
                            Button(label) {
                                switch host {
                                case "retry-summary":  onRetry()
                                case "end-summarize":  onEndSummarize()
                                case "end-force":      onEndForce()
                                default: break
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.blue.opacity(0.12))
                            )
                            .foregroundColor(.blue)
                        }
                    }
                }
            }
        }

        private func stripNMURLs(from text: String) -> String {
            let pattern = "\\[[^\\]]*\\]\\(nm://[a-z-]+\\)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
            let range = NSRange(text.startIndex..., in: text)
            return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
        }

        private func extractNMActions() -> [(String, String)] {
            var actions: [(String, String)] = []
            let regex = try? NSRegularExpression(pattern: "\\[([^\\]]+)\\]\\(nm://([a-z-]+)\\)")
            let matches = regex?.matches(in: msg.content, range: NSRange(msg.content.startIndex..., in: msg.content)) ?? []
            for match in matches {
                guard let labelRange = Range(match.range(at: 1), in: msg.content),
                      let hostRange = Range(match.range(at: 2), in: msg.content) else { continue }
                let label = String(msg.content[labelRange]).trimmingCharacters(in: .whitespaces)
                let host = String(msg.content[hostRange])
                actions.append((host, label))
            }
            return actions
        }

        // MARK: - 内容气泡（AI / 用户 / 思考）

        var contentBubble: some View {
            VStack(alignment: .leading, spacing: 6) {
                // 标题栏 + 复制按钮
                HStack {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(msg.content, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            copied = false
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundColor(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(copied ? localization.copiedTooltip : localization.copyContentTooltip)
                }

                Divider()

                // 内容区
                if msg.sender.hasSuffix(localization.thinkingSuffix) {
                    Text(msg.content)
                        .font(.footnote)
                        .foregroundColor(.gray)
                        .textSelection(.enabled)
                } else if msg.isUser {
                    Text(msg.content)
                        .textSelection(.enabled)
                } else {
                    Markdown(msg.content)
                        .markdownTheme(.meeting)
                        .textSelection(.enabled)
                }
            }
            .padding(12)
            .background(
                msg.sender.hasSuffix(localization.thinkingSuffix)
                    ? Color.gray.opacity(0.08)
                    : msg.isUser
                        ? Color.pink.opacity(0.15)
                        : Color(NSColor.windowBackgroundColor)
            )
            .cornerRadius(10)
        }
    }

    // MARK: - 输入区域

    var inputView: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .center, spacing: 8) {
                GrowingTextEditor(state: editorState, onSubmit: {
                    handleInputSubmit()
                })
                    .padding(.vertical, 4)
                    .frame(height: 74)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                    )

                VStack(spacing: 4) {
                    Button(localization.uploadButton) {
                        handleUpload()
                    }
                    .buttonStyle(.plain)
                    .frame(height: 22)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(currentMeetingTopic == nil ? Color.gray.opacity(0.35) : Color.blue)
                    )
                    .foregroundColor(currentMeetingTopic == nil ? Color.white.opacity(0.5) : .white)
                    .disabled(currentMeetingTopic == nil)

                    Button(localization.submitButton) {
                        submitFinalStatements()
                    }
                    .buttonStyle(.plain)
                    .frame(height: 22)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(secretaryPhase == .done ? Color.orange : Color.gray.opacity(0.35))
                    )
                    .foregroundColor(secretaryPhase == .done ? .white : Color.white.opacity(0.5))
                    .disabled(secretaryPhase != .done)

                    Button(secretaryPhase == .done ? localization.supplementButton : localization.speakButton) {
                        handleInputSubmit()
                    }
                    .buttonStyle(.plain)
                    .frame(height: 22)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(inputButtonDisabled ? Color.gray.opacity(0.35) : Color.green)
                    )
                    .foregroundColor(inputButtonDisabled ? Color.white.opacity(0.5) : .white)
                    .disabled(inputButtonDisabled)
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .frame(height: 95)
    }

    // MARK: - 辅助变量

    var inputButtonDisabled: Bool {
        if inputLocked { return true }
        let textEmpty = editorState.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if secretaryPhase == .done {
            return textEmpty
        }
        return textEmpty || isStreaming || !currentSpeaker.isEmpty
    }

    // MARK: - 输入提交分发

    func handleInputSubmit() {
        // 校验是否有正在进行的会议
        guard currentMeetingTopic != nil else {
            addSystemMessage(localization.pleaseCreateMeeting, bubbleType: .yellow)
            return
        }
        if secretaryPhase == .done {
            submitSupplement()
        } else {
            sendMessage()
        }
    }

    // MARK: - 消息发送

    func sendMessage() {
        guard !ragProcessingInProgress else {
            showTopMessage(localization.ragProcessingWait, type: .red)
            return
        }
        let text = editorState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isStreaming else { return }

        // 检查是否有任何 AI 参会
        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            addSystemMessage(localization.noAIToSpeak, bubbleType: .yellow)
            return
        }

        let userName = Config.shared.userName.isEmpty ? (localization.isChinese ? "我" : "Me") : Config.shared.userName
        messages.append(Message(sender: userName, content: text, isUser: true))
        needsScrollToBottom = true
        saveNewMessagesToDisk()
        editorState.clear()
        isStreaming = true

        currentSpeaker = localization.aiPreparingToSpeak

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

    // MARK: - 概括类需求判断

    private func isSummarizationQuery(_ query: String) -> Bool {
        let docWords = localization.docReferenceWords
        let summaryWords = localization.summaryTriggerWords
        let hasDoc = docWords.contains { query.lowercased().contains($0.lowercased()) }
        let hasSummary = summaryWords.contains { query.lowercased().contains($0.lowercased()) }
        return hasDoc && hasSummary
    }

    private func shouldTriggerRAG(_ query: String) -> Bool {
        let q = query.lowercased()
        if q.count <= 5 { return false }
        let docWords = localization.ragTriggerDocWords
        if docWords.contains(where: { q.contains($0.lowercased()) }) { return true }
        let questionWords = localization.ragTriggerQuestionWords
        if questionWords.contains(where: { q.contains($0.lowercased()) }) { return true }
        let actionWords = localization.ragTriggerActionWords
        if actionWords.contains(where: { q.contains($0.lowercased()) }) { return true }
        return false
    }

    private func parseChineseNumber(_ s: String) -> Int? {
        let map: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9, "十": 10
        ]
        if s.count == 1, let n = map[s.first!] { return n }
        if s == "十" { return 10 }
        if s.hasPrefix("十"), let n = map[s.last!] { return 10 + n }
        if s.hasSuffix("十"), let n = map[s.first!] { return n * 10 }
        if s.contains("十") {
            let parts = s.split(separator: "十", maxSplits: 1)
            let tens = map[parts[0].first!] ?? 1
            let ones = parts.count > 1 ? (map[parts[1].first!] ?? 0) : 0
            return tens * 10 + ones
        }
        return nil
    }

    private func matchDocument(_ query: String, files: [UploadedFileInfo]) -> [(fileName: String, index: Int)] {
        guard !files.isEmpty else { return [] }
        // 0. 优先提取被引用符号包裹的精确文件名（「」、【】、《》、""、''、<>）
        let quotePattern = "「([^」]+)」|【([^】]+)】|《([^》]+)》|\"([^\"]+)\"|'([^']+)'|<([^>]+)>"
        if let regex = try? NSRegularExpression(pattern: quotePattern) {
            let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
            var results: [(String, Int)] = []
            for match in matches {
                for i in 1...6 {
                    if let range = Range(match.range(at: i), in: query) {
                        let input = String(query[range])
                        // 精确匹配：先尝试完整文件名（带后缀）
                        if let index = files.firstIndex(where: { $0.fileName == input }) {
                            results.append((files[index].fileName, index))
                            continue
                        }
                        // 容错匹配：尝试去掉后缀后再匹配
                        let inputNoExt = (input as NSString).deletingPathExtension
                        if let index = files.firstIndex(where: { ($0.fileName as NSString).deletingPathExtension == inputNoExt }) {
                            results.append((files[index].fileName, index))
                        }
                    }
                }
            }
            if !results.isEmpty { return results }
        }
        // 1. 中文数字归一化："第六份"→"第6份"、"第二十一份"→"第21份"
        var normalized = query
        if let regex = try? NSRegularExpression(pattern: "第([一二三四五六七八九十]+)(?=份|个|篇|文档|文件)") {
            let range = NSRange(normalized.startIndex..., in: normalized)
            let matches = regex.matches(in: normalized, range: range).reversed()
            for m in matches {
                guard let r = Range(m.range(at: 1), in: normalized) else { continue }
                let cn = String(normalized[r])
                if let num = parseChineseNumber(cn) {
                    normalized.replaceSubrange(r, with: String(num))
                }
            }
        }
        // 2. 序号匹配：中英文
        let numPattern = try? NSRegularExpression(pattern: localization.documentNumberPattern)
        if let match = numPattern?.firstMatch(in: normalized, range: NSRange(normalized.startIndex..., in: normalized)),
           let range = Range(match.range(at: 1), in: normalized),
           let num = Int(normalized[range]), num > 0, num <= files.count {
            return [(files[num - 1].fileName, num - 1)]
        }
        // 3. 文件名模糊匹配（反向覆盖率算法）
        let qChars = Set(query.lowercased())
        var results: [(String, Int)] = []
        for (i, file) in files.enumerated() {
            let fn = (file.fileName as NSString).deletingPathExtension.lowercased()
            let fnChars = Set(fn)
            // 覆盖率 = 文件名中出现在用户发言里的字符数 / 文件名总字符数
            let covered = fnChars.intersection(qChars).count
            let coverage = Double(covered) / Double(max(fnChars.count, 1))
            if coverage >= 0.5 { results.append((file.fileName, i)) }
        }
        return results
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

        currentSpeaker = "\(cfg.name)\(localization.thinkingProgressSuffix)"
        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
            participants[aiIndex].status = .thinking
        }

        let history = aiMessageHistories[cfg.name]!

        var ragHistory = history
        if let bookmark = meetingDirBookmark,
           let (resolvedDir, isStale) = try? URL.from(securityBookmark: bookmark),
           !isStale,
           resolvedDir.startAccessingSecurityScopedResource() {
            let userText = history.last(where: { $0["role"] == "user" })?["content"] ?? ""
            // 第一层：用户是否标定了特定文档？
            let matched = matchDocument(userText, files: uploadedFiles)
            var hasMatched = false
            for item in matched {
                if let context = try? RAGService.retrieveAllChunks(meetingDir: resolvedDir, targetFileName: item.fileName), !context.isEmpty {
                    print("ℹ️ [RAG精确匹配] 全量注入文件「\(item.fileName)」，内容长度：\(context.count)字符")
                    let label = localization.referenceFromDocument(item.fileName, item.index) + context
                    ragHistory.insert(
                        ["role": "system", "content": label],
                        at: 1
                    )
                    hasMatched = true
                }
            }
            if hasMatched {
                if isSummarizationQuery(userText) {
                    ragHistory.insert(
                        ["role": "system", "content": summarizationPrompt],
                        at: 1
                    )
                }
            // 第二层：是否是概括类需求？
            } else if isSummarizationQuery(userText) {
                if let context = try? RAGService.retrieveAllChunks(meetingDir: resolvedDir), !context.isEmpty {
                    ragHistory.insert(
                        ["role": "system", "content": localization.referenceFromDocuments + context],
                        at: 1
                    )
                    ragHistory.insert(
                        ["role": "system", "content": summarizationPrompt],
                        at: 1
                    )
                }
            // 第三层：普通查询 → TopK 语义检索
            } else if shouldTriggerRAG(userText) {
                if let context = try? RAGService.retrieve(query: userText, meetingDir: resolvedDir, systemPrompt: systemPrompt, historyMessages: history), !context.isEmpty {
                    ragHistory.insert(
                        ["role": "system", "content": localization.referenceFromDocuments + context],
                        at: 1
                    )
                }
            }
            resolvedDir.stopAccessingSecurityScopedResource()
        }

        let thinkingMsg = Message(sender: "\(cfg.name)\(localization.thinkingSuffix)", content: "", isUser: false)
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
                        currentSpeaker = "\(cfg.name)\(localization.speakingProgressSuffix)"
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
            messages: ragHistory,
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
                                messages[index].content = localization.aiCallFailed(error.localizedDescription)
                            }
                        } else {
                            addSystemMessageWithTop(localization.aiCallFailed(error.localizedDescription), topType: .red, bubbleType: .yellow)
                        }
                        if let aiIndex = participants.firstIndex(where: { $0.id == ai.id }) {
                            participants[aiIndex].status = .present
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
                        saveNewMessagesToDisk()
                    }
                    currentStreamMessageID = nil
                    self.speakNext(aiOrder: aiOrder, index: index + 1)
                }
            }
        )
    }

    // MARK: - 秘书汇总触发
    func triggerSummary() {
        guard currentMeetingTopic != nil else {
            addSystemMessage(localization.pleaseCreateMeeting, bubbleType: .yellow)
            return
        }
        guard secretaryPhase == .idle else { return }

        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            addSystemMessage(localization.noAIToSpeak, bubbleType: .yellow)
            return
        }

        guard !isStreaming, currentSpeaker.isEmpty else {
            addSystemMessage(localization.aiSpeakingWait, bubbleType: .yellow)
            return
        }

        let hasHistory = presentAIs.contains { ai in
            let cfg = Config.shared.participants[ai.index]
            guard let history = aiMessageHistories[cfg.name] else { return false }
            return history.contains { $0["role"] == "user" }
        }
        guard hasHistory else {
            messages.append(Message(sender: localization.systemSender, content: localization.noHistoryToConsolidate, isUser: false))
            return
        }

        triggerFinalStatements(for: presentAIs)
    }

    // MARK: - 并行自我总结 + 秘书汇总 内部方法，支持回调
    func triggerFinalStatementsInternal(for aiOrder: [Participant], completion: @escaping (String) -> Void) {
        guard secretaryPhase == .idle else { return }
        secretaryPhase = .collecting
        pendingAIOrder = aiOrder
        secretaryStartTime = Date()

        summaryTimer?.invalidate()
        summaryTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            DispatchQueue.main.async {
                guard let start = secretaryStartTime,
                      let progressID = currentProgressMessageID,
                      let idx = messages.firstIndex(where: { $0.id == progressID }) else { return }
                let elapsed = Date().timeIntervalSince(start)
                let t = String(format: "%.1fs", elapsed)
                switch secretaryPhase {
                case .collecting:
                    messages[idx].content = localization.collectingStatementsProgress(secretaryCollectCompleted, secretaryCollectTotal)
                case .summarizing:
                    messages[idx].content = localization.secretarySummarizing
                default:
                    break
                }
                messages[idx].timerSuffix = t
            }
        }

        for ai in aiOrder {
            if let idx = participants.firstIndex(where: { $0.id == ai.id }) {
                participants[idx].status = .thinking
            }
        }
        currentSpeaker = localization.collectingFinalStatements

        let t0 = String(format: "%.1fs", 0.0)
        let progressContent = localization.collectingStatementsProgress(0, aiOrder.count)
        var progressMsg = Message(sender: localization.systemSender, content: progressContent, isUser: false)
        progressMsg.timerSuffix = t0
        progressMsg.systemBubbleType = .lightBlue
        messages.append(progressMsg)
        showTopMessage(progressContent, type: .darkGreen)
        let progressID = progressMsg.id
        currentProgressMessageID = progressID
        secretaryCollectCompleted = 0
        secretaryCollectTotal = aiOrder.count

        let prompt = finalStatementPrompt

        Task {
            var collected: [String: String] = [:]
            var completedCount = 0

            await withTaskGroup(of: (String, Result<(String, TokenUsage?), Error>).self) { group in
                for ai in aiOrder {
                    let cfg = Config.shared.participants[ai.index]
                    group.addTask {
                        let history = await MainActor.run { aiMessageHistories[cfg.name] ?? [] }
                        var msgs = history
                        msgs.append(["role": "user", "content": prompt])

                        return await withCheckedContinuation { continuation in
                            APIService.callAI(config: cfg, messages: msgs, enableThinking: false, timeout: 300) { result in
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
                            collected[name] = "\(localization.finalStatementGenerationFailed)\(error.localizedDescription)"
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

                currentSpeaker = localization.secretarySummarizing

                let userMessages = self.messages.filter { $0.isUser }.map { $0.content }.joined(separator: "\n\n")
                let aiSections = collected.map { "### \($0.key)\n\n\($0.value)" }.joined(separator: "\n\n---\n\n")
                let combinedText = "\(localization.userStatementHeader)\(userMessages)\n\n---\n\n\(aiSections)"
                let secretaryMessages: [[String: String]] = [
                    ["role": "system", "content": secretarySystemPrompt],
                    ["role": "user", "content": "\(localization.summaryProcessSystemPrompt)\(combinedText)"]
                ]

                APIService.callAI(config: Config.shared.secretary, messages: secretaryMessages, enableThinking: false, timeout: 300) { result in
                    DispatchQueue.main.async {
                        self.summaryTimer?.invalidate()
                        self.summaryTimer = nil
                        self.messages.removeAll { $0.id == progressID }
                        self.currentProgressMessageID = nil
                        self.secretaryStartTime = nil
                        
                        switch result {
                        case .success(let (content, _)):
                            completion(content)
                        case .failure(let error):
                            let fallbackText = aiOrder.map { ai in
                                let name = Config.shared.participants[ai.index].name
                                guard let text = collected[name] else { return localization.noContentForName(name) }
                                return "### \(name)\n\n\(text)"
                            }.joined(separator: "\n\n---\n\n")
                            let errorContent = "# \(localization.secretarySummaryFailed)\n\n\(error.localizedDescription)\n\n---\n\n# \(localization.participantsSummaryHeader)\n\n\(fallbackText)"
                            completion(errorContent)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - 对外汇总方法，保持原有逻辑
    func triggerFinalStatements(for aiOrder: [Participant]) {
        triggerFinalStatementsInternal(for: aiOrder) { [self] summaryContent in
            // 原有汇总流程，进入done状态等待提交
            self.secretaryBaseContent = summaryContent
            let fullContent = self.buildSecretaryDisplayContent()
            let secretaryMsg = Message(sender: localization.secretaryLabel, content: fullContent, isUser: false)
            self.messages.append(secretaryMsg)
            self.secretaryMessageID = secretaryMsg.id
            self.secretaryPhase = .done
            self.currentSpeaker = ""
            self.isStreaming = false
            self.needsScrollToBottom = true
            self.saveNewMessagesToDisk()
        }
    }

    // MARK: - Token 统计

    @State var totalInputTokens: Int = 0
    @State var totalOutputTokens: Int = 0

    // MARK: - 秘书展示构造

    func buildSecretaryDisplayContent() -> String {
        var content = secretaryBaseContent

        if !userSupplement.isEmpty {
            content += localization.secretarySupplement(userSupplement)
        }
        
        let displayName = Config.shared.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (localization.isChinese ? "用户" : "User")
            : Config.shared.userName
        content += localization.secretaryMoreOpinion(displayName)
        return content
    }

    // MARK: - 补充意见

    func submitSupplement() {
        let text = editorState.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard secretaryPhase == .done else { return }

        userSupplement = text
        editorState.clear()

        let userName = Config.shared.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (localization.isChinese ? "用户" : "User")
            : Config.shared.userName
        messages.append(Message(sender: userName, content: text, isUser: true))
        saveNewMessagesToDisk()

        if let msgID = secretaryMessageID,
           let idx = messages.firstIndex(where: { $0.id == msgID }) {
            messages[idx].content = buildSecretaryDisplayContent()
            needsScrollToBottom = true
        }
    }

    // MARK: - 提交最终论述

    func submitFinalStatements() {
        guard secretaryPhase == .done else { return }

        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }

        var anonymousText = secretaryBaseContent

        let aiNames = presentAIs.map { Config.shared.participants[$0.index].name }
        let labels = localization.opinionLabels
        for (i, name) in aiNames.enumerated() {
            guard i < labels.count else { break }
            anonymousText = anonymousText.replacingOccurrences(of: name, with: labels[i])
        }

        var submissionText = anonymousText
        if !userSupplement.isEmpty {
            submissionText += "\n\n---\n\n# \(localization.userSupplementLabel)\n\n\(userSupplement)"
        }

        for ai in presentAIs {
            let name = Config.shared.participants[ai.index].name
            aiMessageHistories[name] = [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": submissionText]
            ]
        }

        // 逐轮存档
        if let meetingDir = meetingDirURL {
            do {
                try MeetingArchiveService.saveRound(round: currentRound, summary: secretaryBaseContent, supplement: userSupplement, meetingDir: meetingDir)
                lastSavedRound = currentRound
                lastSavedMessageCount = messages.count + 1
                messages.append(Message(sender: localization.systemSender, content: localization.roundRecordSaved, isUser: false))
            } catch {
                messages.append(Message(sender: localization.systemSender, content: localization.roundRecordSaveFailed(error.localizedDescription), isUser: false))
            }
        }
        
        userSupplement = ""
        secretaryPhase = .idle
        secretaryBaseContent = ""
        secretaryMessageID = nil
        finalStatements = [:]

        messages.append(Message(sender: localization.systemSender, content: localization.finalStatementsSubmitted, isUser: false))

        // 自动触发参会 AI 盲评发言（基于完整匿名汇总稿，含分歧点总结）
        isStreaming = true
        currentSpeaker = localization.aiPreparingToSpeak
        currentRound += 1
        speakNext(aiOrder: presentAIs, index: 0)
    }

    // MARK: - 重试秘书汇总

    func handleRetrySummary() {
        guard !pendingAIOrder.isEmpty, secretaryPhase == .done else { return }

        secretaryPhase = .idle
        messages.append(Message(sender: localization.systemSender, content: localization.retryingSecretarySummary, isUser: false))
        triggerFinalStatements(for: pendingAIOrder)
    }

    func handleUpload() {
        guard let bookmark = meetingDirBookmark else { return }

        let panel = NSOpenPanel()
        var types: [UTType] = []
        for ext in DocumentParser.supportedExtensions {
            if let type = UTType(filenameExtension: ext) ?? UTType(tag: ext, tagClass: .filenameExtension, conformingTo: .plainText) {
                types.append(type)
            }
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let files = panel.urls
        DispatchQueue.global(qos: .background).async {
            guard let (resolved, isStale) = try? URL.from(securityBookmark: bookmark),
                  !isStale,
                  resolved.startAccessingSecurityScopedResource() else { return }
            defer { resolved.stopAccessingSecurityScopedResource() }

            let uploadsDir = resolved.appendingPathComponent("uploads", isDirectory: true)
            try? FileManager.default.createDirectory(at: uploadsDir, withIntermediateDirectories: true)

            var count = 0
            for url in files {
                let dest = uploadsDir.appendingPathComponent(url.lastPathComponent)
                do { try FileManager.default.copyItem(at: url, to: dest); count += 1 }
                catch {}
            }

            if count > 0 {
                DispatchQueue.main.async {
                    // 创建RAG专属动态气泡
                    var ragMsg = Message(sender: localization.systemSender, content: "\(localization.filesUploaded(count))\n\(localization.buildingIndexProgress)", isUser: false)
                    ragMsg.systemBubbleType = .lightBlue
                    self.messages.append(ragMsg)
                    self.currentRAGProcessingMsgID = ragMsg.id
                    self.ragProcessingInProgress = true
                    self.needsScrollToBottom = true
                    
                    for fileURL in files {
                        self.uploadedFiles.append(UploadedFileInfo(fileName: fileURL.lastPathComponent, uploadTime: Date()))
                    }
                    
                    // 异步构建索引
                    Task {
                        do {
                            try await RAGService.buildIndex(meetingDir: resolved)
                            DispatchQueue.main.async {
                                if let msgID = self.currentRAGProcessingMsgID, let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
                                    var msg = self.messages[idx]
                                    msg.content = "\(localization.filesUploaded(count))\n\(localization.indexBuildComplete)"
                                    msg.systemBubbleType = .lightBlue
                                    self.messages[idx] = msg
                                    self.showTopMessage(localization.indexBuildComplete, type: .darkGreen)
                                }
                                self.ragProcessingInProgress = false
                                self.currentRAGProcessingMsgID = nil
                            }
                        } catch {
                            DispatchQueue.main.async {
                                if let msgID = self.currentRAGProcessingMsgID, let idx = self.messages.firstIndex(where: { $0.id == msgID }) {
                                    var msg = self.messages[idx]
                                    msg.content = "\(localization.filesUploaded(count))\n\(localization.indexBuildFailed(error.localizedDescription))"
                                    msg.systemBubbleType = .yellow
                                    self.messages[idx] = msg
                                    self.showTopMessage(localization.indexBuildFailed(error.localizedDescription), type: .red)
                                }
                                self.ragProcessingInProgress = false
                                self.currentRAGProcessingMsgID = nil
                            }
                        }
                    }
                }
            }
        }
    }

    func endMeeting() {
        guard !hasSpeakingAI() else {
            addSystemMessageWithTop(localization.waitBeforeEndMeeting, topType: .red, bubbleType: .yellow, shouldScrollToBottom: true)
            return
        }
        guard secretaryPhase != .collecting && secretaryPhase != .summarizing else {
            showTopMessage(localization.waitSecretaryConsolidating, type: .red)
            return
        }
        guard !summaryInProgress else {
            showTopMessage(localization.waitSummaryInProgress, type: .red)
            return
        }

        if secretaryPhase == .done {
            saveCurrentDoneState()
            performArchiveAndReset()
            return
        }

        if hasUnsavedContent() {
            showEndMeetingWarning()
        } else {
            performArchiveAndReset()
        }
    }

    func saveCurrentDoneState() {
        guard let meetingDir = meetingDirURL else { return }
        do {
            try MeetingArchiveService.saveRound(round: currentRound, summary: secretaryBaseContent, supplement: userSupplement, meetingDir: meetingDir)
            lastSavedRound = currentRound
            lastSavedMessageCount = messages.count
        } catch {
            messages.append(Message(sender: localization.systemSender, content: localization.errorSaveFailed(error.localizedDescription), isUser: false))
        }
    }

    func showEndMeetingWarning() {
        inputLocked = true
        let content = localization.endMeetingPrompt
        addSystemMessage(content, bubbleType: .yellow, shouldScrollToBottom: true)
    }

    func handleEndSummarize() {
        // 检查是否已选择过结束方式
        guard !isEndingMeeting else {
            showTopMessage(localization.endMethodAlreadySelected, type: .red)
            return
        }
        isEndingMeeting = true
        
        inputLocked = false
        let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
        guard !presentAIs.isEmpty else {
            performArchiveAndReset()
            return
        }
        summaryInProgress = true
        triggerFinalStatementsInternal(for: presentAIs) { [self] summaryContent in
            self.summaryInProgress = false
            if let meetingDir = self.meetingDirURL {
                do {
                    try MeetingArchiveService.saveRound(round: self.currentRound, summary: summaryContent, supplement: "", meetingDir: meetingDir, showUserSupplement: false)
                    self.lastSavedRound = self.currentRound
                    self.lastSavedMessageCount = self.messages.count + 2
                    self.messages.append(Message(sender: localization.secretaryLabel, content: summaryContent, isUser: false))
                } catch {
                    self.messages.append(Message(sender: localization.systemSender, content: localization.errorSaveFailed(error.localizedDescription), isUser: false))
                }
            }
            self.secretaryPhase = .idle
            self.isStreaming = false
            self.currentSpeaker = ""
            self.performArchiveAndReset()
        }
    }

    func handleEndForce() {
        // 检查是否已选择过结束方式
        guard !isEndingMeeting else {
            showTopMessage(localization.endMethodAlreadySelected, type: .red)
            return
        }
        isEndingMeeting = true
        
        performArchiveAndReset()
    }

    func performArchiveAndReset() {
        inputLocked = true

        if meetingDirURL != nil {
            saveMeetingStateToDisk()
            saveMeetingConfigSnapshotToDisk()
        }
        
        stopAutoSaveTimer()
        meetingDurationTimer?.invalidate()

        if let topic = currentMeetingTopic, let meetingDir = meetingDirURL, let startTime = meetingStartTime {
            do {
                let archiveURL = try MeetingArchiveService.archiveMeeting(topic: topic, meetingDir: meetingDir, startTime: startTime)
                let content = localization.meetingEndedArchivePath(archiveURL.path)
                addSystemMessageWithTop(content, topType: .darkGreen, bubbleType: .lightBlue, shouldScrollToBottom: true)
            } catch {
                let content = localization.meetingEndArchiveFailed(error.localizedDescription)
                addSystemMessageWithTop(content, topType: .red, bubbleType: .yellow, shouldScrollToBottom: true)
            }
        } else {
            let content = localization.meetingEndedNotice
            addSystemMessage(content, bubbleType: .lightBlue)
        }

        currentMeetingTopic = nil
        meetingStartTime = nil
        meetingDirURL = nil
        meetingDirBookmark = nil
        meetingDuration = 0
        for i in participants.indices {
            participants[i].status = .away
            participants[i].accumulatedTokens = 0
        }
        aiMessageHistories = [:]
        pendingAIOrder = []
        finalStatements = [:]
        totalInputTokens = 0
        totalOutputTokens = 0
        secretaryPhase = .idle
        isStreaming = false
        currentSpeaker = ""
        currentRound = 1
        userSupplement = ""
        secretaryBaseContent = ""
        secretaryMessageID = nil
        lastSavedRound = 0
        lastSavedMessageCount = 0
        summaryInProgress = false
        uploadedFiles = []
        isEndingMeeting = false
    }
    
    // MARK: - 顶部提示
    
    private func showTopMessage(_ text: String, type: TopMessageType) {
        topMessage = (text, type)
        disappearingText = nil
        originalErrorText = text
        topMessageTimer?.invalidate()
        topMessageTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: false) { _ in
            startDisappearing()
        }
    }
    
    // MARK: - 添加系统消息（支持双提示）
    // 只添加气泡（B1, B4）
    private func addSystemMessage(_ content: String, bubbleType: SystemBubbleType = .lightBlue, shouldScrollToBottom: Bool = false) {
        var msg = Message(sender: localization.systemSender, content: content, isUser: false)
        msg.systemBubbleType = bubbleType
        messages.append(msg)
        if shouldScrollToBottom {
            needsScrollToBottom = true
        }
    }
    
    // 双提示（顶部 + 气泡）：B2, B3
    private func addSystemMessageWithTop(_ content: String, topType: TopMessageType, bubbleType: SystemBubbleType = .lightBlue, shouldScrollToBottom: Bool = false) {
        var msg = Message(sender: localization.systemSender, content: content, isUser: false)
        msg.systemBubbleType = bubbleType
        messages.append(msg)
        showTopMessage(content, type: topType)
        if shouldScrollToBottom {
            needsScrollToBottom = true
        }
    }
    
    // MARK: - 对话实时持久化
    
    private func formatMessageForPersistence(_ msg: Message) -> String? {
        guard msg.sender != localization.systemSender, !msg.sender.hasSuffix(localization.thinkingSuffix) else { return nil }
        
        let type: String
        if msg.isUser {
            type = "USER"
        } else if msg.sender == localization.secretaryLabel {
            type = "SECRETARY"
        } else {
            type = "AI"
        }
        
        // 用独一无二的分隔符，完全不会和内容冲突
        var content = "\n=== MESSAGE START ===\n"
        content += "TYPE: \(type)\n"
        content += "SENDER: \(msg.sender)\n"
        content += "CONTENT:\n"
        content += "\(msg.content)\n"
        content += "=== MESSAGE END ===\n"
        
        return content
    }
    
    private func saveNewMessagesToDisk() {
        guard let meetingDir = meetingDirURL, messages.count > lastSavedMessageCount else { return }
        
        var contentToAppend = ""
        let startIndex = lastSavedMessageCount
        
        for i in startIndex..<messages.count {
            if let formatted = formatMessageForPersistence(messages[i]) {
                contentToAppend += formatted
            }
        }
        
        guard !contentToAppend.isEmpty else {
            lastSavedMessageCount = messages.count
            return
        }
        
        do {
            try MeetingPersistenceService.appendConversation(contentToAppend, meetingDir: meetingDir)
            lastSavedMessageCount = messages.count
        } catch {
            print("\(localization.saveConversationFailed)：\(error.localizedDescription)")
        }
    }
    
    private func parseConversationFromPersistence(content: String) -> [Message] {
        var messages: [Message] = []
        let lines = content.components(separatedBy: "\n")
        
        var currentType: String?
        var currentSender: String?
        var currentContent: String = ""
        var isInContent = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if trimmedLine == "=== MESSAGE START ===" {
                // 新消息开始，重置状态
                currentType = nil
                currentSender = nil
                currentContent = ""
                isInContent = false
            } else if trimmedLine == "=== MESSAGE END ===" {
                // 消息结束，生成Message
                guard let type = currentType, let sender = currentSender, !currentContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    continue
                }
                
                let isUser: Bool
                if type == "USER" {
                    isUser = true
                } else {
                    isUser = false
                }
                
                messages.append(Message(
                    sender: sender,
                    content: currentContent.trimmingCharacters(in: .whitespacesAndNewlines),
                    isUser: isUser
                ))
            } else if isInContent {
                // 正在收集内容，直接追加
                currentContent += line + "\n"
            } else if trimmedLine.starts(with: "TYPE: ") {
                currentType = String(trimmedLine.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if trimmedLine.starts(with: "SENDER: ") {
                currentSender = String(trimmedLine.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if trimmedLine == "CONTENT:" {
                isInContent = true
            }
        }
        
        return messages
    }
    
    private func saveMeetingStateToDisk() {
        guard let meetingDir = meetingDirURL, let topic = currentMeetingTopic, let startTime = meetingStartTime else { return }
        
        var secretaryPhaseString = "idle"
        switch secretaryPhase {
        case .idle: secretaryPhaseString = "idle"
        case .collecting: secretaryPhaseString = "collecting"
        case .summarizing: secretaryPhaseString = "summarizing"
        case .done: secretaryPhaseString = "done"
        }
        
        let state = MeetingState(
            topic: topic,
            startTime: startTime,
            currentRound: currentRound,
            secretaryPhase: secretaryPhaseString,
            lastSavedRound: lastSavedRound,
            lastSavedMessageCount: lastSavedMessageCount,
            uploadedFiles: uploadedFiles
        )
        
        do {
            try MeetingPersistenceService.saveMeetingState(state, meetingDir: meetingDir)
        } catch {
            print("\(localization.saveMeetingStateFailed)：\(error.localizedDescription)")
        }
    }
    
    private func saveMeetingConfigSnapshotToDisk() {
        guard let meetingDir = meetingDirURL else { return }
        
        let participantConfigs = Config.shared.participants.map { p in
            ParticipantConfigSnapshot(name: p.name, model: p.model)
        }
        
        let secretarySnapshot = SecretaryConfigSnapshot(model: Config.shared.secretary.model)
        
        let participantStatusSnapshots = participants.map { p in
            var statusString = "away"
            switch p.status {
            case .away: statusString = "away"
            case .present: statusString = "present"
            case .thinking: statusString = "thinking"
            case .speaking: statusString = "speaking"
            }
            return ParticipantStatusSnapshot(name: Config.shared.participants[p.index].name, status: statusString)
        }
        
        let configSnapshot = MeetingConfigSnapshot(
            userName: Config.shared.userName,
            participants: participantConfigs,
            secretary: secretarySnapshot,
            participantStatuses: participantStatusSnapshots
        )
        
        do {
            try MeetingPersistenceService.saveMeetingConfigSnapshot(configSnapshot, meetingDir: meetingDir)
        } catch {
            print("\(localization.saveConfigSnapshotFailed)：\(error.localizedDescription)")
        }
    }
    
    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            self.performAutoSave()
        }
    }
    
    private func stopAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        autoSaveTimer = nil
    }
    
    private func performAutoSave() {
        guard currentMeetingTopic != nil else { return }
        saveMeetingStateToDisk()
    }
    
    private func resumeMeeting(_ meeting: MeetingHistoryInfo) {
        do {
            let bookmark = try meeting.dirURL.securityBookmark()
            
            // 恢复基础状态
            currentMeetingTopic = meeting.state.topic
            meetingStartTime = meeting.state.startTime
            meetingDirURL = meeting.dirURL
            meetingDirBookmark = bookmark
            meetingDuration = Date().timeIntervalSince(meeting.state.startTime)
            meetingDurationTimer?.invalidate()
            meetingDurationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                meetingDuration = Date().timeIntervalSince(meeting.state.startTime)
            }
            inputLocked = true // 暂时锁定输入，等待记忆注入完成
            currentRound = meeting.state.currentRound + 1
            lastSavedRound = meeting.state.lastSavedRound
            lastSavedMessageCount = meeting.state.lastSavedMessageCount
            uploadedFiles = meeting.state.uploadedFiles
            
            secretaryPhase = .idle
            
            // 恢复参会者状态（如果有 config）
            if let config = meeting.config {
                for i in participants.indices {
                    let name = Config.shared.participants[i].name
                    if let statusSnapshot = config.participantStatuses.first(where: { $0.name == name }) {
                        switch statusSnapshot.status {
                        case "away":
                            participants[i].status = .away
                        case "present":
                            participants[i].status = .present
                        case "thinking":
                            participants[i].status = .thinking
                        case "speaking":
                            participants[i].status = .speaking
                        default:
                            participants[i].status = .away
                        }
                    }
                }
            }
            
            // 清除旧数据
            messages.removeAll()
            aiMessageHistories.removeAll()
            finalStatements.removeAll()
            secretaryBaseContent = ""
            secretaryMessageID = nil
            userSupplement = ""
            currentSpeaker = ""
            isStreaming = false
            topMessage = nil
            
            // 启动自动保存
            startAutoSaveTimer()
            
            // 加载历史对话
            do {
                let conversationContent = try MeetingPersistenceService.loadConversation(meetingDir: meeting.dirURL)
                let parsedMessages = parseConversationFromPersistence(content: conversationContent)
                messages = parsedMessages
                
                // 添加系统提示
                addSystemMessage(localization.resumeMeetingHistory(meeting.state.topic, parsedMessages.count), bubbleType: .lightBlue)
            } catch {
                addSystemMessage(localization.resumeMeetingNoHistory(meeting.state.topic), bubbleType: .lightBlue)
            }
            
            // Phase6：秘书归纳历史总结
            let locHistorySummaryGenerated = localization.historySummaryGenerated
            let locResumeReady = localization.resumeReady
            let locMemoryInjectionPrompt = localization.memoryInjectionPrompt
            let locHistoricalMeetingSummaryLabel = localization.historicalMeetingSummaryLabel
            let locYourLastStatementLabel = localization.yourLastStatementLabel
            let locMemoryInjectionInitialSystem = localization.memoryInjectionInitialSystem
            let locReadyToContinue = localization.readyToContinueResponse
            let locAllParticipantsReady = localization.allParticipantsReady
            let locMemoryInjectionFailed = localization.memoryInjectionFailed
            Task {
                do {
                    let summary = try await prepareMeetingResumeSummary(meetingDir: meeting.dirURL)
                    addSystemMessage(locHistorySummaryGenerated, bubbleType: .lightBlue)
                    
                    // Phase7：给所有参会AI注入记忆
                    let presentAIs = participants.filter { $0.status == .present && isConfigured($0) }
                    guard !presentAIs.isEmpty else {
                        addSystemMessage(locResumeReady, bubbleType: .lightBlue)
                        inputLocked = false
                        return
                    }
                    
                    // 收集每个AI的最后一轮发言
                    let lastSpeeches = collectLastAISpeeches()
                    
                    // 并行给所有AI注入记忆并获取回复
                    try await withThrowingTaskGroup(of: (String, String).self) { group in
                        for ai in presentAIs {
                            let config = Config.shared.participants[ai.index]
                            let lastSpeech = lastSpeeches[config.name] ?? "N/A"
                            let injectPromptBody = locMemoryInjectionPrompt
                            let historyLabel = locHistoricalMeetingSummaryLabel
                            let lastStmtLabel = locYourLastStatementLabel
                            let initialSystem = locMemoryInjectionInitialSystem
                            
                            group.addTask {
                                // 构造注入prompt
                                let injectPrompt = """
\(injectPromptBody)

=== \(historyLabel) ===
\(summary)

=== \(lastStmtLabel) ===
\(lastSpeech)
"""
                                // 初始化该AI的消息历史（必须在主线程执行）
                                 await MainActor.run {
                                     self.ensureHistory(for: config.name)
                                 }
                                
                                // 调用AI获取回复
                                return try await withCheckedThrowingContinuation { continuation in
                                    APIService.callAI(
                                        config: config,
                                        messages: [
                                            ["role": "system", "content": initialSystem],
                                            ["role": "user", "content": injectPrompt]
                                        ],
                                        enableThinking: false
                                    ) { result in
                                        switch result {
                                        case .success(let (content, _)):
                                            let reply = content.trimmingCharacters(in: Foundation.CharacterSet.whitespacesAndNewlines)
                                            continuation.resume(returning: (config.name, reply))
                                        case .failure(let error):
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // 收集所有AI的回复并添加到消息列表
                        for try await (name, reply) in group {
                            // 确保AI确实只回复了要求的内容，不做额外输出
                            let finalReply = reply.contains(locReadyToContinue) ? locReadyToContinue : reply
                            messages.append(Message(sender: name, content: finalReply, isUser: false))
                        }
                    }
                    
                    // 全部完成，解锁输入
                    secretaryPhase = .idle
                    summaryInProgress = false
                    addSystemMessage(locAllParticipantsReady, bubbleType: .lightBlue)
                    inputLocked = false
                    
                } catch {
                    addSystemMessageWithTop(locMemoryInjectionFailed(error.localizedDescription), topType: .red, bubbleType: .yellow, shouldScrollToBottom: true)
                    inputLocked = false
                }
            }
            
        } catch {
            addSystemMessageWithTop(localization.resumeFailed(error.localizedDescription), topType: .red, bubbleType: .yellow, shouldScrollToBottom: true)
        }
    }
    
    // MARK: Phase6: 秘书归纳历史会议总结
    private func prepareMeetingResumeSummary(meetingDir: URL) async throws -> String {
        // 1. 读取所有轮次的汇总文件（round-x.md）
        var roundSummaries: [String] = []
        let fileManager = FileManager.default
        
        let roundsDir = meetingDir.appendingPathComponent("rounds")
        guard fileManager.fileExists(atPath: roundsDir.path) else {
            return localization.historyNoContentFallback(currentMeetingTopic ?? localization.unnamedMeeting)
        }
        
        // 按轮次顺序读取
        for round in 1...100 { // 最多支持100轮，足够用
            let roundFile = roundsDir.appendingPathComponent("round-\(round).md")
            guard fileManager.fileExists(atPath: roundFile.path) else {
                break
            }
            do {
                let content = try String(contentsOf: roundFile, encoding: .utf8)
                roundSummaries.append("\(localization.roundSummaryHeader(round))\(content)")
            } catch {
                continue
            }
        }
        
        guard !roundSummaries.isEmpty else {
            return localization.historyNoContentFallback(currentMeetingTopic ?? localization.unnamedMeeting)
        }
        
        // 2. 构造秘书专用归纳prompt
        let allSummaries = roundSummaries.joined(separator: "\n\n---\n\n")
        let prompt = """
\(localization.historySecretaryPrompt)
\(allSummaries)
"""
        
        // 3. 调用秘书AI生成总结
        return try await withCheckedThrowingContinuation { continuation in
            APIService.callAI(
                config: Config.shared.secretary,
                messages: [
                    ["role": "system", "content": localization.historySecretarySystem],
                    ["role": "user", "content": prompt]
                ],
                enableThinking: false
            ) { result in
                switch result {
                case .success(let (content, _)):
                    continuation.resume(returning: content.trimmingCharacters(in: Foundation.CharacterSet.whitespacesAndNewlines))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: Phase7辅助: 收集每个AI的最后一轮发言
    private func collectLastAISpeeches() -> [String: String] {
        var lastSpeeches: [String: String] = [:]
        
        // 倒序遍历所有消息，找到每个AI的最后一次发言
        for msg in messages.reversed() {
            // 跳过用户、秘书、系统消息，以及思考消息
            guard !msg.isUser && msg.sender != localization.secretaryLabel && msg.sender != localization.systemSender && !msg.sender.hasSuffix(localization.thinkingSuffix) else {
                continue
            }
            
            // 如果这个AI还没有记录最后发言，就保存
            if lastSpeeches[msg.sender] == nil {
                lastSpeeches[msg.sender] = msg.content
            }
            
            // 所有AI都收集到了就可以提前退出
            let presentAINames = participants.filter { $0.status == .present && isConfigured($0) }.map { Config.shared.participants[$0.index].name }
            if lastSpeeches.keys.count >= presentAINames.count {
                break
            }
        }
        
        return lastSpeeches
    }
    
    // MARK: - 红色提示酷炫消失效果
    
    private func startDisappearing() {
        guard let original = originalErrorText else { return }
        disappearingText = original
        var step = 0
        let totalSteps = 8
        disappearingTimer?.invalidate()
        disappearingTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { timer in
            step += 1
            if step > totalSteps {
                timer.invalidate()
                disappearingTimer = nil
                topMessage = nil
                disappearingText = nil
                originalErrorText = nil
                return
            }
            
            // 随机替换字符为空格
            var result = ""
            let removeProbability = Double(step) / Double(totalSteps)
            
            for char in original {
                if Double.random(in: 0...1) < removeProbability {
                    // 随机删这个字符，用空格替代
                    if char.isASCII {
                        result.append(" ")
                    } else {
                        result.append("  ") // 中文用两个空格
                    }
                } else {
                    result.append(char)
                }
            }
            
            disappearingText = result
        }
    }
    
    // MARK: 悄悄问秘书发送逻辑
    private func sendWhisperMessage() {
        let trimmedInput = whisperInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty && !isWhisperLoading else { return }
        
        let userInput = trimmedInput
        whisperInput = ""
        whisperHistoryIndex = -1
        isWhisperLoading = true
        
        whisperMessages.append((isUser: true, content: userInput))
        
        Task {
            do {
                var apiMessages = [["role": "system", "content": localization.whisperSystemPrompt]]
                for msg in whisperMessages {
                    apiMessages.append(["role": msg.isUser ? "user" : "assistant", "content": msg.content])
                }
                apiMessages.append(["role": "user", "content": userInput])
                
                let response = try await withCheckedThrowingContinuation { continuation in
                    APIService.callAI(
                        config: Config.shared.secretary,
                        messages: apiMessages,
                        enableThinking: false
                    ) { result in
                        switch result {
                        case .success(let (content, _)):
                            continuation.resume(returning: content.trimmingCharacters(in: .whitespacesAndNewlines))
                        case .failure(let error):
                            continuation.resume(throwing: error)
                        }
                    }
                }
                
                DispatchQueue.main.async {
                    self.whisperMessages.append((isUser: false, content: response))
                    self.isWhisperLoading = false
                    self.isWhisperInputFocused = true
                }
            } catch {
                DispatchQueue.main.async {
                    self.whisperMessages.append((isUser: false, content: localization.whisperErrorTip))
                    self.isWhisperLoading = false
                    self.isWhisperInputFocused = true
                }
            }
        }
    }
}

