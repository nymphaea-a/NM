import Foundation

class TokenizerService {
    static let shared = try! TokenizerService()

    private let vocab: [String: Int]
    private let vocabScores: [String: Float]
    private let maxLength: Int = 512
    private let bosId: Int = 0
    private let eosId: Int = 2
    private let padId: Int = 1

    init() throws {
        guard let url = Bundle.main.url(forResource: "tokenizer", withExtension: "json") else {
            throw NSError(domain: "TokenizerService", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "tokenizer.json not found in bundle"])
        }

        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let model = json["model"] as! [String: Any]
        let vocabArray = model["vocab"] as! [[Any]]

        var idMap = [String: Int]()
        var scoreMap = [String: Float]()
        for (index, item) in vocabArray.enumerated() {
            let token = item[0] as! String
            let score = (item[1] as! NSNumber).floatValue
            idMap[token] = index
            scoreMap[token] = score
        }

        self.vocab = idMap
        self.vocabScores = scoreMap
    }

    func tokenize(_ text: String) -> (inputIds: [Int32], attentionMask: [Int32]) {
        let words = preTokenize(text)
        var ids: [Int] = [bosId]

        for word in words {
            ids.append(contentsOf: encodeUnigram(word))
        }

        ids.append(eosId)

        if ids.count > maxLength {
            ids = Array(ids.prefix(maxLength - 1)) + [eosId]
        }

        let padCount = maxLength - ids.count
        let inputIds = ids.map { Int32($0) } + Array(repeating: Int32(padId), count: max(0, padCount))
        let attentionMask = ids.map { _ in Int32(1) } + Array(repeating: Int32(0), count: max(0, padCount))

        return (inputIds, attentionMask)
    }
    
    /// 计算文本的token数量（不做截断，用于上下文窗口判断）
    func countTokens(_ text: String) -> Int {
        let words = preTokenize(text)
        var count = 2 // bos + eos
        for word in words {
            count += encodeUnigram(word).count
        }
        return count
    }

    private func preTokenize(_ text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return parts.map { "\u{2581}\(String($0.prefix(200)))" }
    }

    private func encodeUnigram(_ preToken: String) -> [Int] {
        let chars = Array(preToken)
        let n = chars.count

        var bestScore = [Float](repeating: -.infinity, count: n + 1)
        bestScore[0] = 0
        var bestPrev = [Int](repeating: -1, count: n + 1)

        for i in 0..<n {
            guard bestScore[i] > -.infinity else { continue }

            var current = ""
            let maxJ = min(n, i + 40)
            for j in i..<maxJ {
                current.append(chars[j])
                if let score = vocabScores[current] {
                    let newScore = bestScore[i] + score
                    if newScore > bestScore[j + 1] {
                        bestScore[j + 1] = newScore
                        bestPrev[j + 1] = i
                    }
                }
            }
        }

        if bestScore[n] == -.infinity {
            let fallback = String(preToken)
            if let id = vocab[fallback] {
                return [id]
            }
            return chars.compactMap { vocab[String($0)] }
        }

        var tokens: [String] = []
        var pos = n
        while pos > 0 {
            let prev = bestPrev[pos]
            if prev >= 0 {
                tokens.append(String(chars[prev..<pos]))
                pos = prev
            } else {
                pos -= 1
            }
        }
        tokens.reverse()

        return tokens.compactMap { vocab[$0] }
    }
}
