<p align="center">
  <img src="NM/Assets.xcassets/AppIcon.appiconset/NMicon.png" width="128" alt="Normal Meeting Logo">
</p>

<h1 align="center">Normal Meeting</h1>

<p align="center">
  <strong>macOS 原生 AI 圆桌会议模拟器</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-blue" alt="Platform">
  <img src="https://img.shields.io/badge/language-Swift%205.x-orange" alt="Language">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/model-BGE--M3-purple" alt="Model">
  <img src="https://img.shields.io/badge/ModelScope-🤖-blue" alt="ModelScope">
</p>

---

## 这是什么？

Normal Meeting 是一款 macOS 原生桌面应用，模拟多位 AI 角色围绕一个议题进行圆桌讨论。代码全部由 AI 完成（deepseek-v4-pro、doubao-seed-2.0-pro、qwen3.6-plus）。

你发起议题 → AI 依次发言 → 会议秘书汇总观点并指出分歧 → 匿名盲评 → 多轮迭代 → 生成完整纪要。

**核心特色**：每位 AI 拥有独立对话历史，互不知晓对方的发言，确保观点独立性。支持本地 RAG 文档检索（上传 PDF/代码/文本，AI 发言前自动检索相关内容）。

---

## 功能一览

| 功能 | 说明 |
|------|------|
| 🤖 多 AI 圆桌 | 3 位 AI 参会者 + 1 位会议秘书，各自独立上下文 |
| 🔍 RAG 文档检索 | 上传文档 → 自动分块 → 本地 BGE-M3 向量化 → AI 发言前自动检索注入 |
| 📊 四层查询路由 | 精确文件名匹配 → 序号/模糊匹配 → 概括类全量注入 → 语义+关键词混合检索 |
| 🎭 匿名盲评 | AI 名称替换为「观点 A/B/C」，彻底消除身份偏见 |
| 🔄 历史续开 | 完整会议状态持久化，一键续开历史会议 |
| 🤫 悄悄问秘书 | 浮动窗口无痕问答，不影响正式会议 |
| 🌐 多语言 | 中文/英文双版本，切换语言不影响业务逻辑 |
| 🔒 安全存储 | API Key 存入 macOS Keychain，不上传任何服务器 |
| 📝 Markdown 渲染 | AI 发言支持标准 Markdown 格式 |
| 📋 总结 & 汇总 | 可随时生成当前轮纪要，或收集 AI 最终论述生成完整纪要 |

---

## 系统要求

| 项目 | 要求 |
|------|------|
| 操作系统 | macOS 14.0+（Sonoma 及以上） |
| Xcode | 16.0+ |
| Swift | 5.x |
| 硬件 | Apple Silicon（M1 及以上推荐，Intel 兼容但模型推理较慢） |
| AI API | 兼容 OpenAI 接口格式的任意 API（支持思考模式） |

---

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/nymphaea-a/NM.git
cd NM
```

### 2. 下载 BGE-M3 模型

模型文件较大（约 542MB），从 ModelScope 下载：

**[BGE-M3 CoreML — ModelScope](https://modelscope.cn/models/nymphaeavara/bge-m3-coreml)**

下载 `BGE-M3.mlpackage` 文件（或 zip 解压），放入 `NM/RAG/models/` 目录。

> 正确结构：`NM/RAG/models/BGE-M3.mlpackage/Manifest.json`

### 3. 用 Xcode 打开项目

```bash
open NM.xcodeproj
```

### 4. 配置 API

1. 在 Xcode 中运行项目（⌘R）
2. 首次启动会自动打开设置界面
3. 填写你的名字、选择存储路径
4. 配置秘书和 3 位参会 AI 的 API Key 和 API URL
5. API Key 自动存入 macOS Keychain，安全可靠

### 5. 开始会议

1. 点击「新建会议」→ 输入议题（可选上传参考文档）
2. 在输入框输入你的发言 → Enter 发送
3. AI 依次流式发言
4. 秘书生成汇总、分歧总结
5. 进入盲评 → 多轮迭代 → 结束会议

---

## 项目结构

```
NM/
├── NMApp.swift                      # 应用入口
├── ContentView.swift                # 主视图（全部业务逻辑 + UI）
├── FlowchartView.swift              # 会议流程图
├── HelpView.swift                   # 帮助窗口
├── LocalizationManager.swift        # 多语言本地化
├── SettingsView.swift               # 设置面板
├── APIService.swift                 # HTTP 通信层
├── Config.swift                     # 配置数据模型 + Keychain 整合
├── KeychainService.swift            # macOS Keychain 封装
├── MarkdownTheme.swift              # MarkdownUI 自定义主题
├── MeetingManager.swift             # 会议生命周期管理
├── MeetingArchiveService.swift      # 逐轮落地 + 纪要归档
├── MeetingHistory.swift             # 历史会议数据模型
├── MeetingPersistenceService.swift  # 持久化读写
├── HistoryManager.swift             # 历史会议管理
├── HistoryListView.swift            # 历史列表界面
├── NewMeetingView.swift             # 新建会议界面
├── Config.example.json              # 脱敏配置模板
├── Assets.xcassets/                 # 应用图标 + 颜色
└── RAG/
    ├── models/
    │   └── BGE-M3.mlpackage/        # ← 从 ModelScope 下载放入
    ├── tokenizer.json               # Unigram 词表
    ├── DocumentParser.swift         # 文本解析 + 智能分块
    ├── TokenizerService.swift       # Viterbi 分词器
    ├── BGEM3EmbeddingService.swift  # CoreML 推理
    ├── VectorStore.swift            # SQLite + FTS5 向量库
    └── RAGService.swift             # RAG 编排层
```

---

## 技术栈

| 组件 | 技术 |
|------|------|
| UI | SwiftUI + AppKit（NSTextView） |
| AI 调用 | URLSession（REST + SSE 流式） |
| 本地嵌入 | CoreML（BGE-M3）+ Apple Neural Engine |
| 向量存储 | SQLite3 + FTS5 全文索引 |
| 安全存储 | macOS Keychain |
| Markdown | MarkdownUI |
| 并发模型 | Swift Structured Concurrency（async/await + TaskGroup） |
| PDF 解析 | PDFKit |
| 沙盒安全 | macOS App Sandbox + Security-Scoped Bookmark |

---

## 设计理念

- **独立发言**：每位 AI 拥有完全独立的对话历史，确保观点不受其他 AI 影响
- **匿名盲评**：AI 名称替换为「观点A/B/C」，彻底消除身份偏见
- **RAG 零侵入**：文档检索作为独立叠加层，不修改核心状态机
- **单源真理**：文件格式白名单统一维护，确保「能选即能处理」
- **IME 兼容**：单向数据流解决中文输入法组合状态 Bug

---

## 已知限制

- 参会 AI 数量固定为 3 位
- 不支持多会议并行
- 仅支持 macOS 平台（无 iOS/Web 版本）
- 依赖 Apple Silicon 上的 CoreML 推理（Intel Mac 上模型推理较慢）

---

## License

MIT License © 2026 Nymphaea（nymphaea@zohomail.cn)

BGE-M3 模型文件遵循 [BAAI/bge-m3](https://huggingface.co/BAAI/bge-m3) 原始许可（MIT）。模型托管在 [ModelScope](https://modelscope.cn/models/nymphaeavara/bge-m3-coreml)。
