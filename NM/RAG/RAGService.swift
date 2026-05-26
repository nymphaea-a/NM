import Foundation

struct RAGService {
    // 全量注入配置常量
    private static let MAX_MODEL_CONTEXT_WINDOW = 128000
    private static let INJECTION_BUFFER_RATIO = 0.8
    
    private static func getThreshold(for query: String) -> Float {
        let factKeywords = ["是什么", "什么是", "多少", "哪里", "怎么", "如何", "请告诉我", "请问"]
        let openKeywords = ["总结", "分析", "对比", "区别", "不同", "差异", "概要", "核心内容"]
        
        for keyword in factKeywords {
            if query.contains(keyword) {
                return 0.7
            }
        }
        
        for keyword in openKeywords {
            if query.contains(keyword) {
                return 0.5
            }
        }
        
        return 0.6
    }
    static func buildIndex(meetingDir: URL) async throws {
        let startTime = Date()
        let uploadsDir = meetingDir.appendingPathComponent("uploads", isDirectory: true)
        let tokenizer = TokenizerService.shared
        let embeddingService = BGEM3EmbeddingService.shared
        
        // 计时1：打开数据库耗时
        let dbStart = Date()
        // 以只读可写模式打开现有数据库，不删除旧索引文件，保留历史数据
        let store = try VectorStore(queryOnly: meetingDir)
        let dbCost = Date().timeIntervalSince(dbStart)
        print("⏱️  [索引构建] 打开数据库耗时：\(String(format: "%.2f", dbCost))秒")
        
        // 计时2：查询已存在文件+解析目录过滤耗时
        let parseStart = Date()
        // 第一步：先查已索引过的文件列表
        let existedFiles = try store.getExistedSourceFiles()
        
        // 第二步：解析目录时直接过滤掉已存在的旧文件，只解析新增文件，避免冗余解析开销
        let allChunks = try DocumentParser.parseDirectory(uploadsDir)
            .filter { !existedFiles.contains($0.sourceFile) }
        let parseCost = Date().timeIntervalSince(parseStart)
        print("⏱️  [索引构建] 解析文件+过滤耗时：\(String(format: "%.2f", parseCost))秒，新增chunk数：\(allChunks.count)")
        
        guard !allChunks.isEmpty else {
            // 没有新文件需要处理，直接返回
            print("⏱️  [索引构建] 无新增文件，总耗时：\(String(format: "%.2f", Date().timeIntervalSince(startTime)))秒")
            return
        }
        
        // 计时3：所有chunk向量化总耗时
        let embedStart = Date()
        // 第三步：按来源文件分组，只处理新增文件
        let grouped = Dictionary(grouping: allChunks, by: { $0.sourceFile })
        var allVectors: [(texts: [String], vectors: [[Float]], sourceFile: String)] = []
        for (sourceFile, fileChunks) in grouped {
            var texts: [String] = []
            var allIds: [[Int32]] = []
            var allMasks: [[Int32]] = []
            
            // 第一步：先对所有chunk做tokenize（CPU操作，很快）
            for chunk in fileChunks {
                let (ids, mask) = tokenizer.tokenize(chunk.text)
                allIds.append(ids)
                allMasks.append(mask)
                texts.append(chunk.text)
            }
            
            // 调用并发批量推理，M系列芯片默认6并发，速度提升3~5倍，减少资源抢占
            let vectors = try await embeddingService.batchEmbed(inputIdsList: allIds, attentionMaskList: allMasks, maxConcurrent: 6)
            
            allVectors.append((texts, vectors, sourceFile))
        }
        let embedCost = Date().timeIntervalSince(embedStart)
        print("⏱️  [索引构建] 所有chunk向量化耗时：\(String(format: "%.2f", embedCost))秒，平均每个chunk耗时：\(allChunks.count > 0 ? String(format: "%.2f", embedCost/Double(allChunks.count)) : "0")秒")
        
        // 计时4：数据库插入总耗时
        let insertStart = Date()
        for item in allVectors {
            try store.insert(chunks: item.texts, sourceFile: item.sourceFile, vectors: item.vectors)
        }
        let insertCost = Date().timeIntervalSince(insertStart)
        print("⏱️  [索引构建] 数据库插入耗时：\(String(format: "%.2f", insertCost))秒")
        
        let totalCost = Date().timeIntervalSince(startTime)
        print("✅ [索引构建] 总耗时：\(String(format: "%.2f", totalCost))秒")
    }

    static func retrieve(
        query: String,
        meetingDir: URL,
        topK: Int? = nil,
        systemPrompt: String? = nil,
        historyMessages: [[String: String]]? = nil
    ) throws -> String {
        let tokenizer = TokenizerService.shared
        let embeddingService = BGEM3EmbeddingService.shared
        let store = try VectorStore(queryOnly: meetingDir)
        
        // 动态topK逻辑
        let dynamicTopK: Int
        if let customTopK = topK {
            dynamicTopK = customTopK
        } else {
            let totalDocuments = try store.getTotalSourceFiles()
            switch totalDocuments {
            case 0: dynamicTopK = 0
            case 1: dynamicTopK = 5
            case 2: dynamicTopK = 7
            case 3...: dynamicTopK = 10
            default: dynamicTopK = 5
            }
        }

        let (ids, mask) = tokenizer.tokenize(query)
        let queryVector = try embeddingService.embed(inputIds: ids, attentionMask: mask)
        let threshold = getThreshold(for: query)
        let results = try store.search(query: query, queryVector: queryVector, topK: dynamicTopK, threshold: threshold)

        guard !results.isEmpty else { return "" }
        
        // ----------------------
        // 新增：全量注入自动判断逻辑（仅当传入systemPrompt和history时触发）
        // ----------------------
        if let systemPrompt = systemPrompt, let historyMessages = historyMessages {
            print("ℹ️ [RAG增强] 触发全量注入判断...")
            
            // 1. 对检索结果的sourceFile去重，得到所有相关文档列表（完全复用RAG语义匹配结果）
            let relatedFiles = Array(Set(results.map { $0.sourceFile }))
            print("ℹ️ [RAG增强] 语义匹配到\(relatedFiles.count)个相关文档：\(relatedFiles.joined(separator: ", "))")
            
            // 2. 计算已用token总量
            var usedTokens = 0
            usedTokens += tokenizer.countTokens(systemPrompt)
            for msg in historyMessages {
                if let content = msg["content"] {
                    usedTokens += tokenizer.countTokens(content)
                }
            }
            usedTokens += tokenizer.countTokens(query)
            
            // 3. 计算可用注入阈值
            let availableTotalTokens = MAX_MODEL_CONTEXT_WINDOW - usedTokens
            guard availableTotalTokens > 0 else {
                print("⚠️ [RAG增强] 剩余可用token不足，走原有TopK检索逻辑")
                return results.map { "【来源：\($0.sourceFile)】\n\($0.text)" }.joined(separator: "\n\n---\n\n")
            }
            
            let availableInjectTokens = Int(Double(availableTotalTokens) * INJECTION_BUFFER_RATIO)
            print("ℹ️ [RAG增强] 已用token：\(usedTokens)，可用注入阈值：\(availableInjectTokens)")
            
            // 4. 计算所有相关文档的总token（复用RAG现有getAllChunks方法，内容和RAG解析完全一致）
            var totalDocTokens = 0
            var fullDocContent = ""
            for (index, fileName) in relatedFiles.enumerated() {
                do {
                    let allChunks = try store.getAllChunks(targetFile: fileName)
                    guard !allChunks.isEmpty else { continue }
                    
                    // 拼接该文档的完整内容
                    let docContent = allChunks.map { $0.text }.joined(separator: "\n\n")
                    let docTokens = tokenizer.countTokens(docContent)
                    totalDocTokens += docTokens
                    
                    // 格式化输出
                    fullDocContent += "【文档\(index+1)：\(fileName)】\n\(docContent)\n\n"
                    print("ℹ️ [RAG增强] 文档\(index+1)「\(fileName)」token数：\(docTokens)")
                } catch {
                    print("⚠️ [RAG增强] 读取文档「\(fileName)」失败，跳过该文档")
                    continue
                }
            }
            print("ℹ️ [RAG增强] 所有相关文档总token：\(totalDocTokens)")
            
            // 5. 核心判断：总token小于等于阈值则返回全量内容，否则走原有topK逻辑
            if totalDocTokens <= availableInjectTokens && !fullDocContent.isEmpty {
                print("✅ [RAG增强] 触发全量文档注入，总token：\(totalDocTokens) ≤ 可用阈值：\(availableInjectTokens)")
                return fullDocContent.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                print("ℹ️ [RAG增强] 文档总token超出阈值，走原有TopK检索逻辑")
            }
        }
        
        // ----------------------
        // 原有逻辑不变：返回topK chunk结果
        // ----------------------
        return results.map { "【来源：\($0.sourceFile)】\n\($0.text)" }.joined(separator: "\n\n---\n\n")
    }

    static func retrieveAllChunks(meetingDir: URL, targetFileName: String? = nil) throws -> String {
        let store = try VectorStore(queryOnly: meetingDir)
        let allResults = try store.getAllChunks(targetFile: targetFileName)
        guard !allResults.isEmpty else { return "" }
        return allResults.map { "【来源：\($0.sourceFile)】\n\($0.text)" }.joined(separator: "\n\n---\n\n")
    }
}
