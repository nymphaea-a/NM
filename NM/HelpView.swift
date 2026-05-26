import SwiftUI

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localization: LocalizationManager

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localization.helpWindowTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(localization.closeButton) {
                    dismiss()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor)
                )
                .foregroundColor(.white)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section(localization.helpSectionRoundtable, """
                    Normal Meeting 模拟多位 AI 角色围绕一个议题进行圆桌讨论。
                    你发起议题，AI 依次发言，会议秘书汇总各方观点并指出分歧。

                    每位 AI 拥有独立的对话历史，互不知晓对方的发言内容，
                    确保观点独立性。
                    """)

                    section(localization.helpSectionCoreFlow, """
                    1. 打开设置，配置你的名字、存储路径、秘书和参会 AI
                    2. 点击「新建会议」，输入议题，可上传参考文档
                    3. 在输入框输入你的发言，按 Enter 发送
                    4. 参会 AI 依次流式发言（思考过程 + 正式发言）
                    5. 点击「汇总」→ 秘书收集各 AI 最终论述 → 生成完整纪要
                    6. 点击「总结」→ 秘书仅生成当前轮次总结，不重置记忆
                    7. 提交进入盲评：AI 名称替换为「观点 A/B/C」，确保客观
                    8. 点击「结束会议」→ 生成完整会议纪要文件
                    """)

                    section(localization.helpSectionRAG, """
                    上传文档（PDF、代码、文本等 30 种格式）后，AI 发言前会自动
                    从文档中检索相关内容作为参考。

                    • 在输入框输入「文件名」可精确引用特定文档
                    • 输入「文档 3」或「第 3 份」可按序号引用
                    • 输入「帮我总结一下这个文档」会全量注入文档内容
                    • 点击左侧文件列表中的文件名可自动插入引用标记
                    """)

                    section(localization.helpSectionWhisper, """
                    点击秘书旁边的 W 按钮，打开浮动窗口。
                    可直接向秘书提问，不记录到会议历史。
                    支持多轮追问，ESC 关闭，上下键回溯历史输入。

                    秘书正在汇总/总结期间不可用。
                    """)

                    section(localization.helpSectionSummaryVsConsolidate, """
                    • 总结：仅保存秘书总结到文件，不重置记忆，可继续讨论
                    • 汇总：收集各 AI 最终论述 → 秘书生成完整纪要 + 分歧总结
                             → 用户可补充意见 → 提交进入盲评

                    如果内容没有变化，点击汇总会复用上次总结，节省 Token。
                    """)

                    section(localization.helpSectionHistoryResume, """
                    点击工具栏「历史」可查看过往会议列表，点击「续开」继续讨论。

                    续会后 AI 会自动回顾历史总结和各自之前的发言，
                    回复「我准备好继续开会了」后即可正常发言。

                    所有会议数据保存在你指定的存储路径下：
                    「~/存储路径/NM 存档/{会议主题}/」
                    """)

                    section(localization.helpSectionShortcuts, """
                    Enter         发送消息
                    Shift+Enter   输入框内换行
                    ESC           关闭悄悄问窗口
                    上下键         悄悄问窗口历史输入回溯
                    """)

                    section(localization.helpSectionSecurity, """
                    • API Key 存储在 macOS 系统级钥匙串中，不会上传至任何服务器
                    • 所有会议数据仅保存在本地你指定的目录
                    • 应用开启了 macOS App Sandbox 沙盒保护
                    • BGE-M3 文本向量化完全在本地运行，无需联网
                    """)
                }
                .padding(32)
                .frame(maxWidth: 680)
            }
        }
        .frame(minWidth: 520, minHeight: 600)
    }

    private func section(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text(content)
                .font(.body)
                .foregroundColor(.secondary)
                .lineSpacing(4)
        }
    }
}
