import SwiftUI

// MARK: - 流程节点卡片
struct FlowNode: View {
    let emoji: String
    let title: String
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(color)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(emoji).font(.title3)
                    Text(title)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundColor(color.opacity(0.85))
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(4)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
        }
        .frame(width: 270, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
                .stroke(color.opacity(0.5), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
}

// MARK: - 向下箭头 + 标注
struct FlowArrow: View {
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text("↓")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.gray.opacity(0.6))
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.06))
                .cornerRadius(4)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 分支线 + 提示
struct BranchLine: View {
    let color: Color
    let direction: String
    
    var body: some View {
        HStack(spacing: 4) {
            if direction == "left" {
                Image(systemName: "arrow.left")
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.7))
            }
            Rectangle()
                .fill(color.opacity(0.5))
                .frame(width: 24, height: 1)
            if direction == "right" {
                Image(systemName: "arrow.right")
                    .font(.caption2)
                    .foregroundColor(color.opacity(0.7))
            }
        }
    }
}

// MARK: - 循环标注线
struct LoopIndicator: View {
    let newRound: String
    let discussion: String
    
    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption)
                    .foregroundColor(.blue.opacity(0.7))
                Text(newRound)
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.8))
            }
            Rectangle()
                .fill(Color.blue.opacity(0.4))
                .frame(width: 8, height: 2)
            VStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.caption)
                    .foregroundColor(.blue.opacity(0.7))
                Text(discussion)
                    .font(.caption2)
                    .foregroundColor(.blue.opacity(0.8))
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 图例
struct FlowLegend: View {
    let user: String
    let ai: String
    let secretary: String
    let system: String
    let summary: String
    let done: String
    let mainFlow: String
    let loopPath: String
    let independent: String
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 24) {
                legendColor(.red, user)
                legendColor(.blue, ai)
                legendColor(Color(red: 0.6, green: 0.3, blue: 0.8), secretary)
                legendColor(.gray, system)
                legendColor(.orange, summary)
                legendColor(.green, done)
            }
            HStack(spacing: 24) {
                legendLine(.gray, "solid", mainFlow)
                legendLine(.blue, "dashed", loopPath)
                legendLine(Color(red: 0.6, green: 0.3, blue: 0.8), "dashed", independent)
            }
        }
        .font(.caption2)
        .foregroundColor(.secondary)
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .background(Color.gray.opacity(0.04))
        .cornerRadius(10)
    }
    
    private func legendColor(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
        }
    }
    
    private func legendLine(_ color: Color, _ style: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            if style == "solid" {
                Rectangle().fill(color).frame(width: 14, height: 1)
            } else {
                Rectangle()
                    .stroke(color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 14, height: 1)
            }
            Text(label)
        }
    }
}

// MARK: - 主视图
struct FlowchartView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localization: LocalizationManager
    
    private let userC = Color.red.opacity(0.85)
    private let aiC = Color.blue.opacity(0.85)
    private let secC = Color(red: 0.6, green: 0.3, blue: 0.8).opacity(0.85)
    private let sysC = Color.gray.opacity(0.85)
    private let sumC = Color.orange.opacity(0.85)
    private let doneC = Color.green.opacity(0.85)
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localization.flowchartTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(localization.closeButton) { dismiss() }
                    .font(.callout)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(8)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 12)
            
            Divider()
            
            ScrollView {
                VStack(spacing: 0) {
                    FlowNode(
                        emoji: "👤", title: localization.flowNodeUserSpeak,
                        subtitle: "输入议题/观点\n自动同步到所有AI独立历史\n触发AI下一步响应",
                        color: userC
                    )
                    
                    FlowArrow(label: localization.flowArrowSyncToAI)
                    
                    FlowNode(
                        emoji: "🔍", title: localization.flowNodeRAG,
                        subtitle: "四层智能匹配\n语义+关键词混合召回\n全量注入AI上下文",
                        color: sysC
                    )
                    
                    FlowArrow(label: localization.flowArrowInjectContext)
                    
                    HStack(alignment: .center, spacing: 16) {
                        FlowNode(
                            emoji: "🤖", title: localization.flowNodeAISpeak,
                            subtitle: "3位AI独立上下文\n流式输出思考+结果\n互不可见对方发言",
                            color: aiC
                        )
                        
                        Spacer().frame(width: 4)
                        
                        VStack(spacing: 4) {
                            BranchLine(color: sumC, direction: "right")
                            FlowNode(
                                emoji: "📝", title: localization.flowBranchSummary,
                                subtitle: "可选操作\n仅保存当前轮纪要\n不重置上下文\n不进入盲评",
                                color: sumC
                            )
                        }
                        
                        Spacer().frame(width: 4)
                        
                        VStack(spacing: 4) {
                            BranchLine(color: secC, direction: "right")
                            VStack(spacing: 2) {
                                FlowNode(
                                    emoji: "🤫", title: localization.flowBranchWhisper,
                                    subtitle: "独立无痕问答\n多轮上下文追问\n不影响会议流程",
                                    color: secC
                                )
                                Text(localization.flowWhisperIndependent)
                                    .font(.caption2)
                                    .foregroundColor(secC)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    
                    FlowArrow(label: localization.flowArrowSecretarySummary)
                    
                    FlowNode(
                        emoji: "✏️", title: localization.flowNodeSupplement,
                        subtitle: "用户追加观点\n写入对话历史\n秘书同步更新纪要",
                        color: userC
                    )
                    
                    FlowArrow(label: localization.flowArrowAnonymize)
                    
                    FlowNode(
                        emoji: "🎭", title: localization.flowNodeBlindReview,
                        subtitle: "AI身份→观点A/B/C\n重构讨论上下文\n基于匿名稿二次讨论",
                        color: secC
                    )
                    
                    FlowArrow(label: localization.flowArrowArchiveHistory)
                    
                    HStack(alignment: .center, spacing: 16) {
                        VStack(spacing: 4) {
                            FlowNode(
                                emoji: "🔄", title: localization.flowBranchResume,
                                subtitle: "归纳历史总结\n并行注入AI记忆\n跨会议轮次续接",
                                color: sysC
                            )
                            Text(localization.flowResumeInherit)
                                .font(.caption2)
                                .foregroundColor(sysC)
                        }
                        
                        BranchLine(color: sysC, direction: "left")
                        
                        FlowNode(
                            emoji: "⏭️", title: localization.flowNodeRoundPlus,
                            subtitle: "当前轮历史归档\n清空AI上下文\n新轮次初始化",
                            color: sysC
                        )
                    }
                    .padding(.vertical, 8)
                    
                    LoopIndicator(
                        newRound: localization.flowLoopNewRound,
                        discussion: localization.flowLoopDiscussion
                    )
                    
                    FlowArrow(label: localization.flowArrowEndArchive)
                    
                    FlowNode(
                        emoji: "🏁", title: localization.flowNodeEndMeeting,
                        subtitle: "拼接所有轮次汇总\n生成完整会议纪要\n归档全部数据",
                        color: doneC
                    )
                    
                    FlowLegend(
                        user: localization.flowLegendUser,
                        ai: localization.flowLegendAI,
                        secretary: localization.flowLegendSecretary,
                        system: localization.flowLegendSystem,
                        summary: localization.flowLegendSummary,
                        done: localization.flowLegendDone,
                        mainFlow: localization.flowLegendMainFlow,
                        loopPath: localization.flowLegendLoopPath,
                        independent: localization.flowLegendIndependent
                    )
                    .padding(.top, 32)
                    .padding(.bottom, 24)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 920, minHeight: 750)
    }
}
