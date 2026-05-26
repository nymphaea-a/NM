import SwiftUI
import UniformTypeIdentifiers

struct NewMeetingView: View {
    var onCancel: () -> Void
    var onCreate: (String, Date, [URL]) -> Void
    @EnvironmentObject var localization: LocalizationManager

    @State private var topic: String = ""
    @State private var selectedFiles: [URL] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(localization.newMeetingTitle)
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
                Button(localization.cancel) {
                    onCancel()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Button(localization.startMeeting) {
                    onCreate(topic.trimmingCharacters(in: .whitespacesAndNewlines), Date(), selectedFiles)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color.gray.opacity(0.35)
                            : Color.accentColor)
                )
                .foregroundColor(.white)
                .disabled(topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.meetingTopic)
                        .font(.headline)
                    TextField(localization.topicPlaceholder, text: $topic)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.meetingTime)
                        .font(.headline)
                    Text(Date().formatted(date: .complete, time: .shortened))
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(localization.uploadFiles)
                        .font(.headline)
                    Text(localization.uploadSupportHint)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if selectedFiles.isEmpty {
                        Text(localization.noFiles)
                            .font(.body)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(selectedFiles, id: \.self) { url in
                            Text(url.lastPathComponent)
                                .font(.body)
                        }
                    }

                    Button(action: selectFiles) {
                        Label(localization.selectFiles, systemImage: "plus.circle")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: 600)
        }
    }

    private func selectFiles() {
        let panel = NSOpenPanel()
        var types: [UTType] = []
        for ext in DocumentParser.supportedExtensions {
            if let type = UTType(filenameExtension: ext) ?? UTType(tag: ext, tagClass: .filenameExtension, conformingTo: .plainText) {
                types.append(type)
            }
        }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK {
            selectedFiles = panel.urls
        }
    }
}
