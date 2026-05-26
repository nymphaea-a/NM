import Foundation

struct MeetingArchiveService {
    static func saveRound(round: Int, summary: String, supplement: String, meetingDir: URL, showUserSupplement: Bool = true) throws {
        // 获取存储根目录安全访问权限，根目录授权后所有子路径自动获得权限
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMArchiveError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录，请检查存储路径权限"])
        }
        defer {
            // 操作完成后释放根目录权限
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = dateFormatter.string(from: Date())
        
        var content = """
# 第\(round)轮会议记录
**时间**: \(timestamp)

## 秘书汇总
\(summary)
"""
        // 仅当开启时显示用户补充段落
        if showUserSupplement {
            content += """

### 用户补充
\(supplement.isEmpty ? "无" : supplement)
"""
        }
        
        let filePath = MeetingManager.roundFilePath(meetingDir: meetingDir, round: round)
        try content.write(to: filePath, atomically: true, encoding: .utf8)
    }
    
    static func archiveMeeting(topic: String, meetingDir: URL, startTime: Date) throws -> URL {
        // 获取存储根目录安全访问权限，根目录授权后所有子路径自动获得权限
        let (baseURL, hasAccess) = try MeetingManager.getRagBaseDir()
        guard hasAccess else {
            throw NSError(domain: "NMArchiveError", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法访问存储目录，请检查存储路径权限"])
        }
        defer {
            // 操作完成后释放根目录权限
            baseURL.stopAccessingSecurityScopedResource()
        }
        
        let fileManager = FileManager.default
        let roundsDir = meetingDir.appendingPathComponent("rounds", isDirectory: true)
        
        // 1. 读取所有round-x.md文件并按轮次排序
        let roundFiles = try fileManager.contentsOfDirectory(at: roundsDir, includingPropertiesForKeys: [.nameKey], options: .skipsHiddenFiles)
            .filter { $0.lastPathComponent.starts(with: "round-") && $0.pathExtension == "md" }
            .sorted { file1, file2 in
                // 提取轮次数字，按数值排序避免字符串排序问题
                let name1 = file1.lastPathComponent
                let name2 = file2.lastPathComponent
                if let num1 = Int(name1.dropFirst(6).dropLast(3)),
                   let num2 = Int(name2.dropFirst(6).dropLast(3)) {
                    return num1 < num2
                }
                return name1 < name2
            }
        
        // 2. 拼接所有轮次内容
        var fullContent = ""
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let endTime = dateFormatter.string(from: Date())
        let startTimeStr = dateFormatter.string(from: startTime)
        
        // 头部信息
fullContent += """
# \(topic) · 完整会议纪要
开始时间：\(startTimeStr)
结束时间：\(endTime)
总轮次：\(roundFiles.count)轮
"""
        
// 拼接每个轮次的完整内容，每轮前加分隔线和换行，避免格式错乱
for roundFile in roundFiles {
    if let content = try? String(contentsOf: roundFile, encoding: .utf8) {
        fullContent += "\n\n---\n\n"
        fullContent += content
    }
}
        
        // 3. 生成归档文件路径
        let archivePath = MeetingManager.archivePath(meetingDir: meetingDir, topic: topic)
        
        // 4. 写入文件
        try fullContent.write(to: archivePath, atomically: true, encoding: .utf8)
        
        return archivePath
    }
}
