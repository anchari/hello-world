import SwiftUI

struct StoredRecordingsView: View {
    @EnvironmentObject var manager: RecordingManager

    var body: some View {
        NavigationStack {
            Group {
                if manager.recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings",
                        systemImage: "mic.slash",
                        description: Text("Your recordings will appear here")
                    )
                } else {
                    List {
                        ForEach(manager.recordings) { recording in
                            RecordingRow(recording: recording)
                        }
                        .onDelete { indexSet in
                            let toDelete = indexSet.map { manager.recordings[$0] }
                            toDelete.forEach { manager.delete($0) }
                        }
                    }
                }
            }
            .navigationTitle("Recordings")
        }
    }
}

struct RecordingRow: View {
    @EnvironmentObject var manager: RecordingManager
    let recording: Recording

    @State private var title = ""
    @FocusState private var isFocused: Bool

    private var isPlaying: Bool { manager.playingID == recording.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Title", text: $title)
                .font(.headline)
                .focused($isFocused)
                .onSubmit { commitTitle() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitTitle() }
                }

            HStack(spacing: 4) {
                Text(recording.formattedDate)
                Text("·")
                Text(recording.formattedDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if isPlaying {
                PlaybackBar()
                    .padding(.top, 2)
            }

            HStack {
                Button(action: handlePlayPause) {
                    Label(
                        isPlaying ? "Pause" : "Play",
                        systemImage: isPlaying ? "pause.circle.fill" : "play.circle.fill"
                    )
                    .font(.subheadline.weight(.medium))
                }

                Spacer()

                ShareLink(item: recording.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
        .onAppear { title = recording.title }
    }

    private func handlePlayPause() {
        if isPlaying {
            manager.pausePlayback()
        } else {
            manager.play(recording)
        }
    }

    private func commitTitle() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            manager.updateTitle(for: recording.id, title: trimmed)
        } else {
            title = recording.title
        }
    }
}

struct PlaybackBar: View {
    @EnvironmentObject var manager: RecordingManager

    private var progress: Double {
        guard manager.playbackDuration > 0 else { return 0 }
        return min(manager.playbackTime / manager.playbackDuration, 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(height: 3)
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
    }
}
