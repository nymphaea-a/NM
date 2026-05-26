import SwiftUI

struct HistoryListView: View {
    let onDismiss: () -> Void
    let onResume: (MeetingHistoryInfo) -> Void
    @EnvironmentObject var localization: LocalizationManager
    
    @State private var meetings: [MeetingHistoryInfo] = []
    
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(localization.historyTitle)
                .toolbar {
                    ToolbarItem(placement: .automatic) {
                        Button(localization.closeButton) {
                            onDismiss()
                        }
                    }
                }
                .onAppear {
                    reloadMeetings()
                }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
    
    private var content: some View {
        Group {
            if meetings.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text(localization.noHistory)
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(meetings) { meeting in
                        MeetingRow(meeting: meeting, onResume: {
                            onResume(meeting)
                        })
                        .environmentObject(localization)
                    }
                }
                .listStyle(.plain)
            }
        }
    }
    
    private func reloadMeetings() {
        meetings = HistoryManager.shared.loadAllMeetings()
    }
}

private struct MeetingRow: View {
    let meeting: MeetingHistoryInfo
    let onResume: () -> Void
    @EnvironmentObject var localization: LocalizationManager
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.topic)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 12) {
                    Label(formatDate(meeting.startTime), systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Label(localization.roundLabel(meeting.totalRounds), systemImage: "number")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Label(formatDate(meeting.lastModified), systemImage: "pencil")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                onResume()
            } label: {
                Text(localization.resumeButton)
                    .font(.callout)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: localization.isChinese ? "zh_CN" : "en_US")
        return formatter.string(from: date)
    }
}
