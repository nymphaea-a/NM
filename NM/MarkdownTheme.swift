import SwiftUI
import MarkdownUI

// MARK: - 代码块组件（含复制按钮）

struct CodeBlockCopyView: View {
    let content: String
    let language: String?
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let lang = language, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(action: copyCode) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.06))

            Divider()
                .opacity(0.3)

            Text(content)
                .font(.system(.callout, design: .monospaced))
                .padding(12)
        }
        .background(Color.gray.opacity(0.08))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.15), lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(content, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copied = false
        }
    }
}

// MARK: - 自定义会议主题（仿官方 GitHub Theme 链式风格）

extension Theme {
    static let meeting = Theme()
        // 内联代码
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.85))
            BackgroundColor(Color.gray.opacity(0.12))
        }
        // 一级标题
        .heading1 { configuration in
            configuration.label
                .font(.title2)
                .fontWeight(.bold)
                .padding(.bottom, 4)
        }
        // 二级标题
        .heading2 { configuration in
            configuration.label
                .font(.title3)
                .fontWeight(.semibold)
                .padding(.bottom, 3)
        }
        // 三级标题
        .heading3 { configuration in
            configuration.label
                .font(.headline)
                .fontWeight(.semibold)
                .padding(.bottom, 2)
        }
        // 引用块
        .blockquote { configuration in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 3)
                configuration.label
                    .padding(.leading, 12)
                    .padding(.vertical, 8)
                    .foregroundColor(.secondary)
                Spacer(minLength: 0)
            }
            .background(Color.gray.opacity(0.04))
            .cornerRadius(4)
        }
        // 代码块（带复制按钮）
        .codeBlock { configuration in
            CodeBlockCopyView(
                content: configuration.content,
                language: configuration.language
            )
        }
        // 链接
        .link {
            ForegroundColor(.blue)
        }
        // 表格
        .table { configuration in
            configuration.label
                .markdownTableBorderStyle(
                    .init(color: Color.gray.opacity(0.2))
                )
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.gray.opacity(0.04))
                )
        }
}
