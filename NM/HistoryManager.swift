import Foundation

class HistoryManager {
    static let shared = HistoryManager()
    
    private init() {}
    
    func loadAllMeetings() -> [MeetingHistoryInfo] {
        var meetings: [MeetingHistoryInfo] = []
        
        do {
            let (archiveRootURL, hasAccess) = try MeetingManager.getRagBaseDir()
            guard hasAccess else {
                return []
            }
            defer {
                archiveRootURL.stopAccessingSecurityScopedResource()
            }
            
            let subdirs = try FileManager.default.contentsOfDirectory(at: archiveRootURL, includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            
            for subdir in subdirs {
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: subdir.path, isDirectory: &isDir), isDir.boolValue else {
                    continue
                }
                
                if let meeting = loadMeeting(from: subdir) {
                    meetings.append(meeting)
                }
            }
            
            meetings.sort { $0.startTime > $1.startTime }
            
        } catch {
            print("⚠️ 扫描会议目录失败：\(error.localizedDescription)")
        }
        
        return meetings
    }
    
    private func loadMeeting(from dir: URL) -> MeetingHistoryInfo? {
        do {
            let state = try MeetingPersistenceService.loadMeetingState(meetingDir: dir)
            
            var config: MeetingConfigSnapshot? = nil
            do {
                config = try MeetingPersistenceService.loadMeetingConfigSnapshot(meetingDir: dir)
            } catch {
                print("⚠️ 读取会议配置快照失败（可能是旧会议）：\(error.localizedDescription)")
            }
            
            let attrs = try FileManager.default.attributesOfItem(atPath: dir.path)
            let lastModified = attrs[.modificationDate] as? Date ?? state.startTime
            let totalRounds = state.currentRound
            
            return MeetingHistoryInfo(
                topic: state.topic,
                startTime: state.startTime,
                lastModified: lastModified,
                totalRounds: totalRounds,
                dirURL: dir,
                state: state,
                config: config
            )
        } catch {
            print("⚠️ 读取会议状态失败：\(error.localizedDescription)")
            return nil
        }
    }
}
