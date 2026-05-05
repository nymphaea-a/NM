# NM 项目完整文件清单

---

## 一、NM 软件功能概述

### NM 是什么？

NM 是一款 **macOS 多 AI 协同讨论工具**。用户可以召集多个大语言模型（DeepSeek、Qwen、豆包等）作为"会议参与者"，围绕一个议题进行多轮、结构化的严肃方案讨论。核心场景：一个人面对多个 AI，做并行独立咨询 → 匿名盲评 → 秘书汇总 → 决策参考。

### 核心功能链条

```
Round 1：打电话阶段（并行独立发言，互不可见）

用户输入 → AI-1 DeepSeek 发言（历史：[user输入] → DeepSeek发言）
         → AI-2 豆包 发言    （历史：[user输入] → 豆包发言）
         → AI-3 Qwen 发言    （历史：[user输入] → Qwen发言）

关键：AI-2 看不到 AI-1 说了什么，AI-3 也看不到前两位说了什么。
      每位 AI 只看到「用户原始输入 + 自己之前的发言」。
      本质是并行独立咨询，不是圆桌讨论。
────────────────────────────────────────────
                       │ 用户点"汇总"
                       ▼
秘书汇总阶段

Secretary AI → 收集所有 AI 的发言记录
            → 匿名化处理（脱敏，去除 AI 名称）
            → 生成结构化会议纪要
────────────────────────────────────────────
                       │ 用户点"提交"
                       ▼
Round 2+：盲评阶段（延续独立发言，互不可见）

各 AI 上下文重置：只剩 [systemPrompt + 匿名汇总稿]
用户输入 → AI-1 盲评发言（历史：[system + 汇总] → ...）
         → AI-2 盲评发言
         → AI-3 盲评发言

关键：盲评阶段 AI 看不到彼此的原始身份，消除品牌/权威偏差。
      用户可多轮重复（提交→再盲评→再提交）。
────────────────────────────────────────────
                       │ 用户点"最终提交"
                       ▼
最终汇总

Secretary AI → 综合所有轮次发言
            → 输出最终决策建议 + 分歧点记录
```

### 关键设计理念

- **独立上下文**：每个 AI 有独立的 `aiMessageHistories[ai.name]`，发言互不写入对方历史
- **并行咨询**：Round 1 是三个专家各自独立给建议，不是互相讨论
- **匿名盲评**：提交后上下文重置为匿名汇总稿，消除 AI 之间的品牌偏见
- **秘书角色**：独立的 AI 负责汇总，不参与辩论，保持中立
- **可回溯快照**：每次提交保存历史快照，可随时回顾

---

## 二、项目文件清单

### 项目根目录 `/Users/nomo1982/noizelab/NM/`

| 文件名 | 后缀 | 功能 |
|--------|------|------|
| `.gitignore` | — | Git 忽略规则。屏蔽 Xcode 用户数据（`*.xcuserdata`、`DerivedData`）、工作区文件，以及含 API 密钥的 `NM/Config.json` |
| `NM.xcodeproj/` | 目录 | Xcode 项目文件包，包含构建配置、签名设置、Swift Package 依赖声明等 |

---

### 源代码目录 `/NM/`

#### 1. `NMApp.swift`

| 属性 | 内容 |
|------|------|
| **作用** | 应用程序入口点 |
| **代码行数** | 27 行 |
| **核心职责** | `@main` 标记的 App 结构体；配置 `WindowGroup` 窗口标题为"NM 多 AI 讨论会"；设置默认窗口大小 `minWidth: 900, minHeight: 700` |

---

#### 2. `Config.json`

| 属性 | 内容 |
|------|------|
| **作用** | API 配置文件（含密钥，Git 忽略，不进版本库） |
| **代码行数** | 22 行 |
| **核心职责** | 存储 4 个 AI 的 API 连接信息：<br>• `deepseek`：apiKey, baseURL, model<br>• `qwen`：apiKey, baseURL, model<br>• `doubao`：apiKey, baseURL, model<br>• `secretary`：apiKey, baseURL, model<br><br>注意：此文件包含明文 API Key，已在 `.gitignore` 中排除。开源时需提供 `Config.example.json` 模板 |

---

#### 3. `Config.swift`

| 属性 | 内容 |
|------|------|
| **作用** | Config.json 的 Swift 解码层 |
| **代码行数** | 29 行 |
| **核心职责** | `AIConfig` 结构体（apiKey, baseURL, model）<br>`GlobalConfig` 结构体（包含 4 个 `AIConfig`）<br>`Config.shared` 单例：从 `Bundle.main` 加载并解析 `Config.json`，文件缺失或解析失败则 `fatalError` |

---

#### 4. `APIService.swift`

| 属性 | 内容 |
|------|------|
| **作用** | 大模型 API 调用核心 |
| **代码行数** | 266 行 |
| **核心职责** | **数据模型**：<br>• `ChatResponse` / `Choice` / `MessageContent`：非流式响应结构<br>• `StreamDelta` / `StreamChoice` / `StreamResponse`：流式 SSE 响应结构<br>• `TokenUsage`：token 用量统计（prompt_tokens, completion_tokens, total_tokens）<br><br>**核心方法**：<br>• `callAI()`：通用非流式 API 调用，支持 `enableThinking` 参数控制 reasoning 模式<br>• `streamAI()`：流式 SSE API 调用，逐 token 回调 `onToken`（区分 reasoning/content），完成后回调 `onComplete`，返回 TokenUsage<br>• `callSecretary()` / `streamSecretary()`：秘书专属的非流式/流式 API 调用（强制关闭 thinking 模式）<br><br>**底层实现**：基于 `URLSession`，解析 OpenAI 兼容的 `/chat/completions` 接口，流式请求使用 `line-by-line` SSE 解析 |

---

#### 5. `ContentView.swift`

| 属性 | 内容 |
|------|------|
| **作用** | 主界面 + 全部业务逻辑 |
| **代码行数** | ~1139 行（项目最大文件，占总量 ~76%） |
| **核心职责** | 见下方详细拆分 |

**ContentView 内部模块拆分**：

| 模块 | 大致行号 | 功能 |
|------|---------|------|
| **数据模型** | 头部 | `Participant`（参会AI：name, role, status, accumulatedTokens）<br>`Message`（聊天消息：sender, content, isUser, id）<br>`AIStatus`（.present / .away / .speaking / .thinking）<br>`SecretaryPhase`（.idle / .collecting / .summarizing / .done）<br>`TokenBuffer`（流式 buffer，分离 reasoning 和 content） |
| **主状态** | `@State` 区 | `participants`（3 AI + 1 秘书）<br>`messages`（聊天界面消息列表）<br>`aiMessageHistories`（`[String: [[String: String]]]`，每个 AI 的独立对话历史）<br>`secretaryPhase` / `secretaryBaseContent`<br>`currentSpeaker`（状态栏当前发言者）<br>`isStreaming`（防重复提交锁） |
| **侧边栏 UI** | ~150-370 行 | 参会者状态卡片（头像 emoji、名称、token 计数、状态切换按钮）<br>秘书操作区（汇总按钮 + 进度显示）<br>各 AI 思考面板（可折叠，查看 reasoning process） |
| **聊天 UI** | ~370-450 行 | `ScrollView` + `LazyVStack` 消息列表<br>`MessageBubble` 气泡渲染（支持 Markdown、重试按钮）<br>输入框（`ChatTextEditor`）+ 发言/提交按钮<br>`VSplitView` 布局：上聊天区 + 下输入区 |
| **sendMessage()** | ~637 行 | 用户发言入口：校验输入 → 检查是否有参会 AI → 追加系统消息 → 将用户发言分别 append 到每个参会 AI 的 `aiMessageHistories` → 调用 `speakNext()` 逐一发言 |
| **speakNext()** | ~500-635 行 | **核心引擎**：递归调用链<br>1. 取当前 AI 的独立 `history`（只含用户输入 + 该 AI 自己之前的发言）<br>2. 创建思考面板消息<br>3. 流式调用 `streamAI`，分离 reasoning / content 输出<br>4. 完成后将 assistant 回复写入该 AI 自己的 `aiMessageHistories`<br>5. `self.speakNext(aiOrder: aiOrder, index: index + 1)` 递归调用下一位<br><br>**关键：AI-N 的回复只写入 AI-N 自己的历史，不写入其他 AI 的历史。各 AI 完全隔离。** |
| **通话 vs 盲评分支** | speakNext 内部 | 根据 `secretaryPhase` 判断模式：<br>• 打电话阶段（`secretaryPhase != .done`）：systemPrompt 为角色扮演提示词<br>• 盲评阶段（`secretaryPhase == .done`）：systemPrompt 注入匿名汇总稿，AI 基于汇总稿发表评议 |
| **triggerSummary()** | ~700+ 行 | 触发秘书汇总：检查是否有发言记录 → 收集所有 AI 发言 → 调用秘书 API 生成匿名汇总稿 → 写入 `secretaryBaseContent` |
| **submitFinalStatements()** | ~500+ 行 | 提交按钮逻辑：触发并行自我总结 → 秘书汇总 → 保存快照 → **重置所有 AI 上下文**：`aiMessageHistories[aiName] = [systemPrompt + 匿名汇总稿]` → 切换至盲评阶段（`secretaryPhase = .done`） |
| **triggerFinalStatements()** | ~670 行 | 并行收集各 AI 最终论述（`TaskGroup` 并发请求）→ 进度条动画 → 汇总后传给秘书 |
| **ensureHistory()** | 工具方法 | 确保某 AI 在 `aiMessageHistories` 中有初始化的上下文（systemPrompt），不存在则创建 |
| **秘书进度动画** | ~445 行 | `Timer` 驱动的进度条：旋转动画 + 实时耗时（`X.Xs`） |
| **token 格式化** | 工具方法 | `formatTokens()`：将 token 数格式化为 "1.2K" / "15.3K" 等可读格式 |
| **MessageBubble** | 尾部 | 消息气泡渲染组件：<br>• Markdown 渲染（`MarkdownUI`）<br>• 用户消息右对齐蓝色气泡 / AI 消息左对齐灰色气泡<br>• 系统消息居中淡化<br>• 重试按钮（秘书汇总失败时）<br>• 思考面板折叠/展开 |

---

#### 6. `MarkdownTheme.swift`

| 属性 | 内容 |
|------|------|
| **作用** | Markdown 渲染主题定制 |
| **代码行数** | ~70 行 |
| **核心职责** | 基于 `swift-markdown-ui` 库的自定义主题：<br>• 代码块样式（背景色、字体 `.system(.caption, design: .monospaced)`）<br>• 行内代码样式<br>• 标题、引用块、表格的颜色与间距<br>• 适配 macOS 深色/浅色模式 |

---

### 资源目录 `/NM/Assets.xcassets/`

| 文件路径 | 作用 |
|----------|------|
| `Contents.json` | Asset Catalog 元数据（Xcode 自动生成） |
| `AccentColor.colorset/Contents.json` | 应用主题色配置 |
| `AppIcon.appiconset/Contents.json` | 应用图标配置（尺寸规格定义，当前为空占位） |

---

### 项目配置文件 `NM.xcodeproj/project.pbxproj`

| 配置项 | 值 |
|--------|-----|
| 目标平台 | macOS 26.4（Xcode 26.4.1） |
| 产品名 | NM.app |
| Bundle ID | `com.noizelab.NM` |
| 开发团队 | `9G532FPPQJ` |
| Swift 版本 | 5.0 |
| 外部依赖 | `swift-markdown-ui`（SPM，>= 2.4.1，镜像源 gitcode.com） |
| App Sandbox | ✅ 已启用 |
| Hardened Runtime | ✅ 已启用 |
| 网络权限 | 仅出站连接（`ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES`） |
| 文件访问 | 只读用户选定文件（`ENABLE_USER_SELECTED_FILES = readonly`） |
| 其他资源权限 | 全部禁用（音频/蓝牙/日历/摄像头/通讯录/定位/打印/USB） |

---

## 三、汇总统计

| 指标 | 数值 |
|------|------|
| Swift 源文件 | 5 个 |
| JSON 配置文件 | 1 个（Config.json，Git 忽略） |
| 资源目录 | 1 个（Assets.xcassets，空图标） |
| 项目配置文件 | 1 个（project.pbxproj） |
| 总代码行数 | ~1500 行 |
| 核心文件 | ContentView.swift（~76% 代码量，~1139 行） |
| 外部依赖 | 1 个（swift-markdown-ui） |
| 支持的 LLM | 3 个参会 AI + 1 个秘书 AI |
| 平台 | macOS only（SwiftUI + AppKit） |

---

## 四、架构特点与待改进项

### 现有架构特点

1. **单文件巨型 View**：全部 UI + 全部业务逻辑集中在 `ContentView.swift`，适合快速迭代但不便维护
2. **独立上下文隔离**：`aiMessageHistories` 字典实现 AI 间完全隔离，是并行咨询的核心设计
3. **流式 + 非流式双模式**：`streamAI` 用于实时发言展示，`callAI` 用于秘书非流式汇总
4. **零外部运行时依赖**：只依赖 `swift-markdown-ui`（纯 Swift 包），无 Python/Node/Docker 依赖
5. **Config 外部化**：API Key 通过 JSON 文件注入，代码不硬编码密钥

### 建议后续重构项

| 优先级 | 项目 | 说明 |
|--------|------|------|
| 🔴 高 | Config 设置面板 | 将 Config.json 编辑从手动改文件变为 UI 内设置页 |
| 🔴 高 | Config.example.json | 开源时提供模板文件，隐藏真实密钥 |
| 🟡 中 | ContentView 拆分 | 将业务逻辑抽到 ViewModel / Service 层 |
| 🟡 中 | 文件上传功能 | 支持 md/docx/pdf 上传，全文拼接或 RAG 检索 |
| 🟢 低 | 跨平台评估 | 如需 Windows，考虑 Vapor 本地 Server + Web 前端 |