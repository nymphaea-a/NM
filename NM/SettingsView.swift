import SwiftUI

// MARK: - 设置面板

struct SettingsView: View {
    var dismissAction: (() -> Void)?
    @EnvironmentObject var localization: LocalizationManager

    private func close() {
        dismissAction?()
    }

    // 直接从 Documents 中的 Config.json 加载和保存
    @State private var userName: String = ""

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

    @State private var selectedStorageURL: URL?
    @State private var customStorageBookmark: Data?
    @State private var errorMessage: String? = nil
    @State private var selectedLanguage: AppLanguage = LocalizationManager.shared.language

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack {
                Text(localization.settingsTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(localization.cancel) {
                    close()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Button(localization.confirm) {
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

            Divider()

            // ── 错误提示 ──
            if let error = errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
            }

            // ── 主内容区域 ──
            HStack(alignment: .top, spacing: 24) {
                // 左列: 用户信息 + 秘书
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text(localization.userInfo)
                            .font(.headline)
                        labeledField(localization.yourName, text: $userName, prompt: localization.namePrompt)
                    }
                    
                    Divider()
                    
                    Group {
                        Text(localization.storageSettings)
                            .font(.headline)
                        Text(localization.storageDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        HStack(spacing: 8) {
                            TextField(localization.storageNotSelected, text: .constant(selectedStorageURL?.path ?? ""))
                                .textFieldStyle(.roundedBorder)
                                .font(.body)
                                .disabled(true)
                            Button(localization.selectStorage) {
                                selectStoragePath()
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                            )
                        }
                    }

                    Divider()

                    Group {
                        Text(localization.meetingSecretary)
                            .font(.headline)
                        Text(localization.secretaryDescription)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        labeledSecureField(localization.apiKey, text: $secretaryAPIKey, prompt: "sk-...")
                        labeledField(localization.apiURL, text: $secretaryBaseURL, prompt: "https://api.example.com")
                        labeledField(localization.modelLabel, text: $secretaryModel, prompt: localization.modelPlaceholder)
                    }
                    
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                            Text(localization.thinkingModelInfo)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.secondary)
                            Text(localization.keychainSecurityInfo)
                                .font(.callout)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 4)

                    // 语言设置
                    Group {
                        Text(localization.languageLabel)
                            .font(.headline)
                        Picker("", selection: $selectedLanguage) {
                            Text("中文").tag(AppLanguage.chinese)
                            Text("English").tag(AppLanguage.english)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 200)
                    }
                    
                    Divider()

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                // 右列: 3 位参会 AI
                VStack(alignment: .leading, spacing: 16) {
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

                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
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
            Text(localization.participantAILabel(index - 1))
                .font(.headline)

            labeledField(localization.participantName, text: name, prompt: localization.participantNamePlaceholder)
            labeledSecureField(localization.apiKey, text: apiKey, prompt: "sk-...")
            labeledField(localization.apiURL, text: baseURL, prompt: "https://api.example.com")
            labeledField(localization.modelLabel, text: model, prompt: localization.participantModelPlaceholder)
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
        let config = Config.shared
        userName = config.userName
        customStorageBookmark = config.customStorageBookmark
        
        // 从书签还原URL用于显示
        if let bookmark = customStorageBookmark {
            do {
                let (url, isStale) = try URL.from(securityBookmark: bookmark)
                if isStale {
                    errorMessage = localization.errorStorageExpired
                    selectedStorageURL = nil
                    customStorageBookmark = nil
                } else {
                    selectedStorageURL = url
                }
            } catch {
                errorMessage = localization.errorStorageInvalid
                selectedStorageURL = nil
                customStorageBookmark = nil
            }
        }

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

        // 2. 校验必填
        guard !uName.isEmpty else {
            errorMessage = localization.errorNameRequired
            return
        }
        
        guard let storageBookmark = customStorageBookmark, let storageURL = selectedStorageURL else {
            errorMessage = localization.errorStorageRequired
            return
        }
        
        // 校验存储路径有效性和写入权限
        do {
            // 获取安全访问权限
            guard storageURL.startAccessingSecurityScopedResource() else {
                errorMessage = localization.errorStorageAccessDenied
                return
            }
            defer {
                storageURL.stopAccessingSecurityScopedResource()
            }
            
            try FileManager.default.createDirectory(at: storageURL, withIntermediateDirectories: true)
            let testFileURL = storageURL.appendingPathComponent(".nm_write_test_\(UUID().uuidString)")
            try "test".write(to: testFileURL, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(at: testFileURL)
        } catch {
            errorMessage = localization.errorStorageNoWritePermission(error.localizedDescription)
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
            errorMessage = localization.errorSecretaryRequired
            return
        }

        // 5. 校验部分填写的参会 AI —— 允许全空，也允许全填满，但不允许只填一部分
        if !p1Configured.allFilled && p1Configured.anyFilled {
            errorMessage = localization.errorParticipantIncomplete(0)
            return
        }
        if !p2Configured.allFilled && p2Configured.anyFilled {
            errorMessage = localization.errorParticipantIncomplete(1)
            return
        }
        if !p3Configured.allFilled && p3Configured.anyFilled {
            errorMessage = localization.errorParticipantIncomplete(2)
            return
        }

        // 6. 保存到 Keychain
        SecretaryConfig(apiKey: secKey, baseURL: secURL, model: secModel).saveToKeychain()
        
        let participants = [
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
        
        for p in participants where !p.apiKey.isEmpty {
            p.saveToKeychain()
        }

        // 7. 构建 AppConfig 并写入 Documents
        let newConfig = AppConfig(
            userName: uName,
            secretaryModel: secModel,
            participantNames: participants.map(\.name),
            participantModels: participants.map(\.model),
            customStorageBookmark: storageBookmark
        )

        Config.save(appConfig: newConfig)
        Config.reload()
        // 应用语言设置
        localization.setLanguage(selectedLanguage)
        close()
    }

    // MARK: - 辅助方法
    
    private func selectStoragePath() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = localization.selectStorageTitle
        panel.prompt = localization.selectButton
        
        if panel.runModal() == .OK, let url = panel.url {
            selectedStorageURL = url
            do {
                // 生成安全书签
                customStorageBookmark = try url.securityBookmark()
                errorMessage = nil
            } catch {
                errorMessage = localization.errorStorageBookmarkAccessDenied(error.localizedDescription)
                selectedStorageURL = nil
                customStorageBookmark = nil
            }
        }
    }

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

}