import Foundation
import SQLite3

class VectorStore {
    private var db: OpaquePointer?
    private let dimension = 1024

    convenience init(queryOnly meetingDir: URL) throws {
        try self.init(meetingDir: meetingDir)
    }

    private init(meetingDir: URL) throws {
        let dbURL = meetingDir.appendingPathComponent("search.db")

        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db!))
            throw NSError(domain: "VectorStore", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to open search.db: \(msg)"])
        }

        sqlite3_exec(db!, "PRAGMA journal_mode=DELETE;", nil, nil, nil)
        sqlite3_exec(db!, "PRAGMA locking_mode=NORMAL;", nil, nil, nil)
        // 同步级别设为FULL，确保插入的数据立刻持久化到磁盘，不会丢失
        sqlite3_exec(db!, "PRAGMA synchronous=FULL;", nil, nil, nil)

        // 不管是否新建表，都确保chunks表存在
        let createSQL = """
        CREATE TABLE IF NOT EXISTS chunks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            text TEXT NOT NULL,
            source_file TEXT NOT NULL,
            vector BLOB NOT NULL
        );
        """
        if sqlite3_exec(db!, createSQL, nil, nil, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db!))
            throw NSError(domain: "VectorStore", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create chunks table: \(msg)"])
        }
        
        // 不管是否新建表，都确保FTS5全文检索表存在
        let createFtsSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS chunks_fts USING fts5(
            text,
            source_file UNINDEXED,
            content='chunks',
            content_rowid='id'
        );
        """
        sqlite3_exec(db!, createFtsSQL, nil, nil, nil)
    }

    deinit {
        sqlite3_close(db!)
    }

    func insert(chunks: [String], sourceFile: String, vectors: [[Float]]) throws {
        guard chunks.count == vectors.count else {
            throw NSError(domain: "VectorStore", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "chunks and vectors count mismatch"])
        }

        let insertSQL = "INSERT INTO chunks (text, source_file, vector) VALUES (?, ?, ?);"
        let ftsInsertSQL = "INSERT INTO chunks_fts(rowid, text, source_file) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        var ftsStmt: OpaquePointer?
        
        // 显式开启事务，批量插入只需要一次事务开销，性能提升10倍以上
        guard sqlite3_exec(db!, "BEGIN TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "VectorStore", code: -6,
                userInfo: [NSLocalizedDescriptionKey: "Failed to start transaction"])
        }
        
        defer {
            // 无论是否成功都提交/回滚事务
            if sqlite3_exec(db!, "COMMIT TRANSACTION;", nil, nil, nil) != SQLITE_OK {
                sqlite3_exec(db!, "ROLLBACK TRANSACTION;", nil, nil, nil)
            }
        }
        
        // 预编译SQL语句，只需要编译一次
        guard sqlite3_prepare_v2(db!, insertSQL, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_prepare_v2(db!, ftsInsertSQL, -1, &ftsStmt, nil) == SQLITE_OK else {
            throw NSError(domain: "VectorStore", code: -7,
                userInfo: [NSLocalizedDescriptionKey: "Failed to prepare insert statements"])
        }
        defer {
            sqlite3_finalize(stmt)
            sqlite3_finalize(ftsStmt)
        }
        
        for i in 0..<chunks.count {
            let vector = vectors[i]
            guard vector.count == dimension else { continue }

            let blob = vector.withUnsafeBytes { Data($0) }
            let text = chunks[i]
            
            // 绑定参数插入主表
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(stmt, 2, sourceFile, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            _ = blob.withUnsafeBytes { ptr in
                sqlite3_bind_blob(stmt, 3, ptr.baseAddress, Int32(blob.count), nil)
            }
            
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                continue
            }
            
            // 插入FTS索引表
            let rowId = sqlite3_last_insert_rowid(db!)
            sqlite3_reset(ftsStmt)
            sqlite3_bind_int64(ftsStmt, 1, rowId)
            sqlite3_bind_text(ftsStmt, 2, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_text(ftsStmt, 3, sourceFile, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_step(ftsStmt)
        }
    }

    func getTotalSourceFiles() throws -> Int {
        let selectSQL = "SELECT COUNT(DISTINCT source_file) FROM chunks;"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db!, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        
        var count = 0
        if sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int(stmt, 0))
        }
        sqlite3_finalize(stmt)
        return count
    }
    
    /// 获取已索引过的所有来源文件名列表
    func getExistedSourceFiles() throws -> Set<String> {
        let selectSQL = "SELECT DISTINCT source_file FROM chunks;"
        var stmt: OpaquePointer?
        
        guard sqlite3_prepare_v2(db!, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        
        var files = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let namePtr = sqlite3_column_text(stmt, 0) else { continue }
            let name = String(cString: namePtr)
            files.insert(name)
        }
        sqlite3_finalize(stmt)
        return files
    }

    func search(query: String, queryVector: [Float], topK: Int, threshold: Float = 0.6) throws -> [(text: String, sourceFile: String, similarity: Float)] {
        guard queryVector.count == dimension else {
            throw NSError(domain: "VectorStore", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "queryVector dimension mismatch"])
        }
        
        // 1. 先查询BM25关键词得分（如果FTS表存在）
        var bm25Scores: [Int64: Float] = [:]
        let ftsSQL = "SELECT rowid, bm25(chunks_fts) FROM chunks_fts WHERE chunks_fts MATCH ?;"
        var ftsStmt: OpaquePointer?
        if sqlite3_prepare_v2(db!, ftsSQL, -1, &ftsStmt, nil) == SQLITE_OK {
            sqlite3_bind_text(ftsStmt, 1, query, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(ftsStmt) == SQLITE_ROW {
                let rowId = sqlite3_column_int64(ftsStmt, 0)
                let bm25 = sqlite3_column_double(ftsStmt, 1)
                // BM25得分越小越相关，反转后归一化到0~1
                let normalized = 1.0 / (1.0 + Float(bm25))
                bm25Scores[rowId] = normalized
            }
            sqlite3_finalize(ftsStmt)
        }

        // 2. 查询所有chunk的文本、来源、向量和rowid
        let selectSQL = "SELECT id, text, source_file, vector FROM chunks;"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db!, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }

        struct ScoredChunk {
            let text: String
            let sourceFile: String
            let similarity: Float // 融合后的最终得分
            let rowId: Int64
        }
        var results: [ScoredChunk] = []

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            guard let textPtr = sqlite3_column_text(stmt, 1),
                  let sourceFilePtr = sqlite3_column_text(stmt, 2),
                  let blobPtr = sqlite3_column_blob(stmt, 3) else { continue }

            let text = String(cString: textPtr)
            let sourceFile = String(cString: sourceFilePtr)
            let blobSize = sqlite3_column_bytes(stmt, 3)
            let count = Int(blobSize) / 4

            var storedVector = [Float](repeating: 0, count: count)
            blobPtr.withMemoryRebound(to: Float.self, capacity: count) { ptr in
                for i in 0..<count {
                    storedVector[i] = ptr[i]
                }
            }

            // 计算语义相似度（BGE-M3向量已归一化，点积直接为cosine相似度0~1）
            var semanticScore: Float = 0
            let minDim = min(storedVector.count, queryVector.count)
            for i in 0..<minDim {
                semanticScore += storedVector[i] * queryVector[i]
            }
            semanticScore = max(0, min(1, semanticScore)) // 确保在0~1区间
            
            // 融合BM25关键词得分（语义70%权重，关键词30%权重）
            let bm25Score = bm25Scores[rowId] ?? 0.3
            let finalScore = semanticScore * 0.7 + bm25Score * 0.3

            results.append(ScoredChunk(text: text, sourceFile: sourceFile, similarity: finalScore, rowId: rowId))
        }
        sqlite3_finalize(stmt)

        results.sort { $0.similarity > $1.similarity }
        
        // 阈值过滤：只保留相似度>=threshold的chunk
        let filteredResults = results.filter { $0.similarity >= threshold }
        
        // 多文档均衡采样：每个来源至少取1个chunk
        var chunksBySource: [String: [ScoredChunk]] = [:]
        for chunk in filteredResults {
            chunksBySource[chunk.sourceFile, default: []].append(chunk)
        }
        
        var finalResults: [ScoredChunk] = []
        var usedTexts = Set<String>()
        
        // 第一轮：每个来源取相似度最高的1个
        for (_, chunks) in chunksBySource {
            if let topChunk = chunks.first {
                finalResults.append(topChunk)
                usedTexts.insert(topChunk.text)
            }
        }
        
        // 第二轮：补全剩余名额
        let remainingSlots = topK - finalResults.count
        if remainingSlots > 0 {
            let remainingChunks = results
                .filter { !usedTexts.contains($0.text) }
                .prefix(remainingSlots)
            finalResults.append(contentsOf: remainingChunks)
        }
        
        // 最终按相似度排序
        finalResults.sort { $0.similarity > $1.similarity }
        return finalResults.map { (text: $0.text, sourceFile: $0.sourceFile, similarity: $0.similarity) }
    }

    func getAllChunks(targetFile: String? = nil) throws -> [(text: String, sourceFile: String)] {
        let selectSQL = targetFile != nil
            ? "SELECT text, source_file FROM chunks WHERE source_file = ? ORDER BY id;"
            : "SELECT text, source_file FROM chunks ORDER BY id;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db!, selectSQL, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        if let target = targetFile {
            sqlite3_bind_text(stmt, 1, target, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }
        var results: [(text: String, sourceFile: String)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let textPtr = sqlite3_column_text(stmt, 0),
                  let sourceFilePtr = sqlite3_column_text(stmt, 1) else { continue }
            results.append((String(cString: textPtr), String(cString: sourceFilePtr)))
        }
        sqlite3_finalize(stmt)
        return results
    }
}
