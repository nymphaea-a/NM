import SwiftUI

// MARK: - 设置面板

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss

    // 直接从 Documents 中的 Config.json 加载和保存
    @State private var userName: String = ""
    @State private var meetingName: String = ""

    // 秘书
    @State private var secretaryAPIKey: String = ""
    @State private var secretaryBaseURL: String = ""
    @State private var secretaryModel: String = ""

    // 参会 AI
    @State private var p1Name: String = ""
    @State private var p1APIKey: String = ""
    @State private var p1BaseURL: String = ""
    @State private var p1Model: String = ""

    @State private var p2Name: String = ""
    @State private var p2APIKey: String = ""
    @State private var p2BaseURL: String = ""
    @State private var p2Model: String = ""

    @State private var p3Name: String = ""
    @State private var p3APIKey: String = ""
    @State private var p3BaseURL: String = ""
    @State private var p3Model: String = ""

    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text("⚙ 设置")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // ── 用户信息 ──
                    Group {
                        Text("用户信息")
                            .font(.headline)
                        labeledField("你的名字", text: $userName, prompt: "例如：nomo")
                        labeledField("会议名称", text: $meetingName, prompt: "例如：产品方案评审会")
                    }

                    Divider()

                    // ── 参会 AI ──
                    participantSection(
                        index: 1,
                        name: $p1Name,
                        apiKey: $p1APIKey,
                        baseURL: $p1BaseURL,
                        model: $p1Model
                    )

                    Divider()

                    participantSection(
                        index: 2,
                        name: $p2Name,
                        apiKey: $p2APIKey,
                        baseURL: $p2BaseURL,
                        model: $p2Model
                    )

                    Divider()

                    participantSection(
                        index: 3,
                        name: $p3Name,
                        apiKey: $p3APIKey,
                        baseURL: $p3BaseURL,
                        model: $p3Model
                    )

                    Divider()

                    // ── 会议秘书 ──
                    Group {
                        Text("会议秘书")
                            .font(.headline)

                        Text("秘书为必填项，负责汇总各方论述并生成会议纪要。")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        labeledSecureField("API Key", text: $secretaryAPIKey, prompt: "sk-...")
                        labeledField("API URL", text: $secretaryBaseURL, prompt: "https://api.example.com")
                        labeledField("模型", text: $secretaryModel, prompt: "例如：qwen3.5-plus")
                    }

                    Divider()

                    // ── 思考模式说明 ──
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("ℹ️ 本会议室仅支持可开启思考模式的 AI 模型（OpenAI 兼容模式）参会。会议秘书使用非思考模式 AI。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // ── 安全声明 ──
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "lock.shield")
                            .foregroundColor(.secondary)
                        Text("🔒 API 密钥仅保存在本地，不会上传至任何服务器。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // ── 错误提示 ──
                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.red.opacity(0.08))
                            )
                    }
                }
                .padding()
            }

            Divider()

            // 底部按钮
            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Button("确定") {
                    saveConfig()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .padding()
        }
        .frame(width: 500, height: 700)
        .onAppear {
            loadCurrentConfig()
        }
    }

    // MARK: - 参会 AI Section

    func participantSection(
        index: Int,
        name: Binding<String>,
        apiKey: Binding<String>,
        baseURL: Binding<String>,
        model: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参会 AI ②\("①②③"[index])")
                .font(.headline)

            labeledField("名称", text: name, prompt: "例如：小鲸鱼")
            labeledSecureField("API Key", text: apiKey, prompt: "sk-...")
            labeledField("API URL", text: baseURL, prompt: "https://api.example.com")
            labeledField("模型", text: model, prompt: "例如：deepseek-v4-pro")
        }
    }

    // MARK: - 表单字段

    func labeledField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .trailing)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .autocorrectionDisabled(true)
        }
    }

    func labeledSecureField(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 68, alignment: .trailing)
            SecureField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
                .font(.body)
                .autocorrectionDisabled(true)
        }
    }

    // MARK: - 加载当前配置

    func loadCurrentConfig() {
        let config = loadDocumentsConfig()
        userName = config.userName
        meetingName = config.meetingName

        secretaryAPIKey = config.secretary.apiKey
        secretaryBaseURL = config.secretary.baseURL
        secretaryModel = config.secretary.model

        if config.participants.count > 0 {
            p1Name = config.participants[0].name
            p1APIKey = config.participants[0].apiKey
            p1BaseURL = config.participants[0].baseURL
            p1Model = config.participants[0].model
        }
        if config.participants.count > 1 {
            p2Name = config.participants[1].name
            p2APIKey = config.participants[1].apiKey
            p2BaseURL = config.participants[1].baseURL
            p2Model = config.participants[1].model
        }
        if config.participants.count > 2 {
            p3Name = config.participants[2].name
            p3APIKey = config.participants[2].apiKey
            p3BaseURL = config.participants[2].baseURL
            p3Model = config.participants[2].model
        }
    }

    // MARK: - 校验与保存

    func saveConfig() {
        // 1. 清除旧错误
        errorMessage = nil

        let uName = userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let mName = meetingName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 2. 校验必填
        guard !uName.isEmpty else {
            errorMessage = "请填写你的名字"
            return
        }

        guard !mName.isEmpty else {
            errorMessage = "请填写会议名称"
            return
        }

        // 3. 校验至少一位参会 AI
        let p1Configured = isParticipantFilled(name: p1Name, apiKey: p1APIKey, baseURL: p1BaseURL, model: p1Model)
        let p2Configured = isParticipantFilled(name: p2Name, apiKey: p2APIKey, baseURL: p2BaseURL, model: p2Model)
        let p3Configured = isParticipantFilled(name: p3Name, apiKey: p3APIKey, baseURL: p3BaseURL, model: p3Model)

        // 4. 校验秘书必填
        let secKey = secretaryAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let secURL = secretaryBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let secModel = secretaryModel.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !secKey.isEmpty, !secURL.isEmpty, !secModel.isEmpty else {
            errorMessage = "会议秘书为必填项，请完整填写 API Key、API URL 和模型"
            return
        }

        // 5. 校验部分填写的参会 AI —— 允许全空，也允许全填满，但不允许只填一部分
        if !p1Configured.allFilled && p1Configured.anyFilled {
            errorMessage = "参会 AI ① 的字段未填写完整（名称、API Key、API URL、模型均需填写）"
            return
        }
        if !p2Configured.allFilled && p2Configured.anyFilled {
            errorMessage = "参会 AI ② 的字段未填写完整（名称、API Key、API URL、模型均需填写）"
            return
        }
        if !p3Configured.allFilled && p3Configured.anyFilled {
            errorMessage = "参会 AI ③ 的字段未填写完整（名称、API Key、API URL、模型均需填写）"
            return
        }

        // 6. 构建 AppConfig 并写入 Documents
        let newConfig = AppConfig(
            userName: uName,
            meetingName: mName,
            secretary: SecretaryConfig(
                apiKey: secKey,
                baseURL: secURL,
                model: secModel
            ),
            participants: [
                ParticipantConfig(
                    name: p1Name.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: p1APIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: p1BaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: p1Model.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                ParticipantConfig(
                    name: p2Name.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: p2APIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: p2BaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: p2Model.trimmingCharacters(in: .whitespacesAndNewlines)
                ),
                ParticipantConfig(
                    name: p3Name.trimmingCharacters(in: .whitespacesAndNewlines),
                    apiKey: p3APIKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseURL: p3BaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                    model: p3Model.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            ]
        )

        saveToDocuments(newConfig)
        dismiss()
    }

    // MARK: - 辅助方法

    struct FilledStatus {
        let allFilled: Bool
        let anyFilled: Bool
    }

    func isParticipantFilled(name: String, apiKey: String, baseURL: String, model: String) -> FilledStatus {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let k = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let u = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let any = !n.isEmpty || !k.isEmpty || !u.isEmpty || !m.isEmpty
        let all = !n.isEmpty && !k.isEmpty && !u.isEmpty && !m.isEmpty
        return FilledStatus(allFilled: all, anyFilled: any)
    }

    // MARK: - 文件 IO

    func loadDocumentsConfig() -> AppConfig {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL.appendingPathComponent("Config.json")

        if fileManager.fileExists(atPath: configURL.path) {
            do {
                let data = try Data(contentsOf: configURL)
                return try JSONDecoder().decode(AppConfig.self, from: data)
            } catch {
                // 如果解析失败，返回默认空配置
            }
        }
        // 如果 Documents 中还没有，从当前全局配置取
        return Config.shared
    }

    func saveToDocuments(_ config: AppConfig) {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let configURL = documentsURL.appendingPathComponent("Config.json")

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL)
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }
}