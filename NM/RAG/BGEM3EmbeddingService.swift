import CoreML
import Foundation

class BGEM3EmbeddingService {
    private let model: MLModel

    static let shared = try! BGEM3EmbeddingService()

    init() throws {
        print("🚀 [BGEM3] 开始加载模型，当前时间：\(Date())")
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine // 只用CPU+神经网络引擎，避开GPU兼容性bug，性能足够

        guard let compiledURL = Bundle.main.url(forResource: "BGE-M3", withExtension: "mlmodelc") else {
            throw NSError(domain: "BGEM3EmbeddingService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "BGE-M3.mlmodelc not found in bundle"])
        }

        self.model = try MLModel(contentsOf: compiledURL, configuration: config)
        print("✅ [BGEM3] 模型加载完成，当前时间：\(Date())")
    }

    /// 单样本推理接口（兼容原有代码，同步实现，不依赖异步批量方法）
    func embed(inputIds: [Int32], attentionMask: [Int32]) throws -> [Float] {
        let seqLength = inputIds.count

        let inputIdsArray = try MLMultiArray(shape: [1, NSNumber(value: seqLength)], dataType: .int32)
        let attentionMaskArray = try MLMultiArray(shape: [1, NSNumber(value: seqLength)], dataType: .int32)

        for i in 0..<seqLength {
            inputIdsArray[i] = NSNumber(value: inputIds[i])
            attentionMaskArray[i] = NSNumber(value: attentionMask[i])
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": inputIdsArray,
            "attention_mask": attentionMaskArray,
        ])

        let output = try model.prediction(from: input)
        guard let embeddingArray = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw NSError(domain: "BGEM3EmbeddingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "embedding not found in model output"])
        }

        let count = embeddingArray.count
        var result = [Float](repeating: 0, count: count)
        for i in 0..<count {
            result[i] = embeddingArray[i].floatValue
        }

        return result
    }
    
    /// 并发批量推理接口（Swift结构化并发实现），无需修改CoreML模型，自动利用多核提升速度3~5倍
    /// - Parameters:
    ///   - inputIdsList: 批量inputIds数组，每个元素对应一个Chunk的ids
    ///   - attentionMaskList: 批量attentionMask数组，长度和inputIdsList一致
    ///   - maxConcurrent: 最大并发数，M系列芯片推荐8，性能压力大可以降到4
    /// - Returns: 批量embedding结果，每个元素对应一个Chunk的1024维向量，顺序和输入保持一致
    func batchEmbed(inputIdsList: [[Int32]], attentionMaskList: [[Int32]], maxConcurrent: Int = 8) async throws -> [[Float]] {
        let count = inputIdsList.count
        guard count > 0 else { return [] }
        guard inputIdsList.count == attentionMaskList.count else {
            throw NSError(domain: "BGEM3EmbeddingService", code: -3, userInfo: [NSLocalizedDescriptionKey: "inputIdsList and attentionMaskList count mismatch"])
        }
        
        let concurrency = min(maxConcurrent, count)
        return try await withThrowingTaskGroup(of: (Int, [Float]).self) { group in
            var results = [(Int, [Float])]()
            results.reserveCapacity(count)
            
            // 控制并发数，防止同时创建太多任务爆内存
            for (idx, (inputIds, attentionMask)) in zip(inputIdsList, attentionMaskList).enumerated() {
                // 超过并发数时先等待一个任务完成再添加新任务
                if idx >= concurrency {
                    if let completed = try await group.next() {
                        results.append(completed)
                    }
                }
                
                // 添加新的推理任务
                group.addTask {
                    let embedding = try self.embed(inputIds: inputIds, attentionMask: attentionMask)
                    return (idx, embedding)
                }
            }
            
            // 收集剩余所有任务的结果
            for try await completed in group {
                results.append(completed)
            }
            
            // 按原输入顺序排序，保证结果顺序正确
            results.sort { $0.0 < $1.0 }
            return results.map { $0.1 }
        }
    }
}
