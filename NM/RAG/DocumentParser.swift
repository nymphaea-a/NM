import Foundation
import PDFKit

struct DocumentChunk {
    let text: String
    let sourceFile: String
    let chunkIndex: Int
}

struct DocumentParser {
    static let supportedExtensions: Set<String> = ["txt", "md", "pdf", "json", "py", "swift", "js", "ts", "jsx", "tsx", "java", "cpp", "c", "h", "hpp", "rb", "go", "rs", "sh", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sql", "r", "m", "mm"]

    private static let maxCharsPerChunk = 2048

    static func parseDirectory(_ dir: URL) throws -> [DocumentChunk] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
            .filter { url in
                supportedExtensions.contains(url.pathExtension.lowercased())
            }

        var allChunks: [DocumentChunk] = []
        for file in files {
            let fileChunks = try parseFile(file)
            allChunks.append(contentsOf: fileChunks)
        }
        return allChunks
    }

    static func parseFile(_ url: URL) throws -> [DocumentChunk] {
        let text = try extractText(from: url)
        let paragraphs = splitIntoParagraphs(text)
        let chunks = chunkParagraphs(paragraphs, sourceFile: url.lastPathComponent)
        return chunks
    }

    private static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let pdf = PDFDocument(url: url) else {
                throw NSError(domain: "DocumentParser", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PDF 无法解析: \(url.lastPathComponent)"])
            }
            if let text = pdf.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
            var fallback = ""
            for i in 0..<pdf.pageCount {
                if let page = pdf.page(at: i) {
                    fallback += page.attributedString?.string ?? page.string ?? ""
                }
            }
            let result = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty {
                throw NSError(domain: "DocumentParser", code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "PDF 无法提取文字: \(url.lastPathComponent)"])
            }
            return result
        }
        if supportedExtensions.contains(ext) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        return ""
    }

    private static func splitIntoParagraphs(_ text: String) -> [String] {
        let raw = text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return raw
    }

    private static func chunkParagraphs(_ paragraphs: [String], sourceFile: String) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        var currentBuffer = ""
        var index = 0
        
        for para in paragraphs {
            // 如果当前缓冲区加这个段落还没超过2048字符，就合并（+2是段落之间的两个换行符）
            if currentBuffer.count + para.count + 2 <= maxCharsPerChunk {
                if !currentBuffer.isEmpty {
                    currentBuffer += "\n\n"
                }
                currentBuffer += para
            } else {
                // 缓冲区满了，先把缓冲区的内容存成chunk
                if !currentBuffer.isEmpty {
                    chunks.append(DocumentChunk(text: currentBuffer, sourceFile: sourceFile, chunkIndex: index))
                    index += 1
                    currentBuffer = ""
                }
                // 新段落如果本身就超过2048字符，就切割长段落
                if para.count > maxCharsPerChunk {
                    let sub = splitLongParagraph(para)
                    for s in sub {
                        chunks.append(DocumentChunk(text: s, sourceFile: sourceFile, chunkIndex: index))
                        index += 1
                    }
                } else {
                    // 新段落不超过2048，放进缓冲区
                    currentBuffer = para
                }
            }
        }
        // 最后把剩下的缓冲区内容存成chunk
        if !currentBuffer.isEmpty {
            chunks.append(DocumentChunk(text: currentBuffer, sourceFile: sourceFile, chunkIndex: index))
        }
        return chunks
    }

    private static func splitLongParagraph(_ text: String) -> [String] {
        let breakChars = CharacterSet(charactersIn: "。.！!？?\n")
        let scanner = Scanner(string: text)
        scanner.charactersToBeSkipped = nil

        var result: [String] = []
        var current = ""

        while !scanner.isAtEnd {
            if let segment = scanner.scanUpToCharacters(from: breakChars) {
                current += segment
            }
            if let punct = scanner.scanCharacters(from: breakChars) {
                current += punct
                // 长段落切割阈值1800字符，尽量接近maxCharsPerChunk，减少chunk数量
                if current.count >= 1800 {
                    result.append(current.trimmingCharacters(in: .whitespaces))
                    current = ""
                }
            }
        }
        if !current.isEmpty {
            result.append(current.trimmingCharacters(in: .whitespaces))
        }
        return result.filter { !$0.isEmpty }
    }
}
