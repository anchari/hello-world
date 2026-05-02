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

    private var isActive: Bool { manager.playingID == recording.id }
    private var isPlaying: Bool { isActive && !manager.isPlaybackPaused }

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

            if isActive {
                PlaybackBar()
                    .padding(.vertical, 4)
            }

            HStack {
                Spacer()
                controlButton("gobackward.10", enabled: isActive) { manager.skip(by: -10) }
                Spacer()
                Button(action: handlePlayPause) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                }
                Spacer()
                controlButton("goforward.10", enabled: isActive) { manager.skip(by: 10) }
                Spacer()
                controlButton("trash", color: .red) { manager.delete(recording) }
                Spacer()
                ShareLink(item: recording.url) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
        .onAppear { title = recording.title }
    }

    private func handlePlayPause() {
        if isPlaying {
            manager.pausePlayback()
        } else if isActive {
            manager.resumePlayback()
        } else {
            manager.play(recording)
        }
    }

    @ViewBuilder
    private func controlButton(
        _ icon: String,
        color: Color = .primary,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(enabled ? color : Color(.systemGray3))
        }
        .disabled(!enabled)
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
