import SwiftUI

struct StoredRecordingsView: View {
    @EnvironmentObject var manager: RecordingManager
    @EnvironmentObject var transcriptionManager: TranscriptionManager

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
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    let recording: Recording

    @State private var title = ""
    @State private var transcript: Transcript? = nil
    @State private var transcriptExpanded = false
    @State private var confirmDelete = false
    @FocusState private var isFocused: Bool

    private var isActive: Bool  { manager.playingID == recording.id }
    private var isPlaying: Bool { isActive && !manager.isPlaybackPaused }
    private var isTranscribing: Bool { transcriptionManager.transcribingIDs.contains(recording.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title
            TextField("Title", text: $title)
                .font(.headline)
                .focused($isFocused)
                .onSubmit { commitTitle() }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitTitle() }
                }

            // Metadata
            HStack(spacing: 4) {
                Text(recording.formattedDate)
                Text("·")
                Text(recording.formattedDuration)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // Playback progress bar
            if isActive {
                PlaybackBar()
                    .padding(.vertical, 4)
            }

            // Playback controls
            HStack(spacing: 0) {
                HStack(spacing: 0) {
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
                    ShareLink(item: recording.url) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Divider().padding(.horizontal, 12)

                controlButton("trash", color: .red) { confirmDelete = true }
                    .padding(.trailing, 8)
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
            .confirmationDialog("Delete this recording?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { manager.delete(recording) }
                Button("Cancel", role: .cancel) {}
            }

            // Transcript section
            transcriptSection
        }
        .padding(.vertical, 6)
        .onAppear {
            title = recording.title
            transcript = transcriptionManager.loadTranscript(for: recording)
        }
        .onChange(of: transcriptionManager.transcribingIDs) { _, ids in
            if !ids.contains(recording.id) {
                transcript = transcriptionManager.loadTranscript(for: recording)
            }
        }
    }

    // MARK: - Transcript section

    @ViewBuilder
    private var transcriptSection: some View {
        if isTranscribing {
            HStack(spacing: 6) {
                ProgressView()
                    .scaleEffect(0.7)
                Text("Transcribing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        } else if let transcript {
            VStack(alignment: .leading, spacing: 6) {
                // Header row
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { transcriptExpanded.toggle() } }) {
                    HStack {
                        Text(transcriptExpanded ? "Transcript" : previewText(transcript))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(transcriptExpanded ? nil : 1)
                        Spacer()
                        Image(systemName: transcriptExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if transcriptExpanded {
                    if transcript.engine == .appleSFSpeech {
                        Text("Transcribed using built-in ASR")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }

                    if transcript.segments.isEmpty {
                        // Flat text fallback (SFSpeech draft)
                        Text(transcript.fullText.isEmpty ? "No transcript available." : transcript.fullText)
                            .font(.callout)
                            .foregroundStyle(.primary)
                            .padding(.top, 2)
                    } else {
                        // Timestamped segments with playback sync
                        TranscriptSegmentsView(
                            segments: transcript.segments,
                            currentTime: isActive ? manager.playbackTime : -1
                        )
                    }

                    // Share transcript button
                    if !transcript.fullText.isEmpty {
                        ShareLink(item: transcript.fullText, subject: Text(recording.title), message: Text("")) {
                            Label("Share Transcript", systemImage: "envelope")
                                .font(.caption.weight(.medium))
                        }
                        .buttonStyle(.borderless)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.top, 4)
        }
    }

    private func previewText(_ transcript: Transcript) -> String {
        let text = transcript.fullText.isEmpty ? transcript.segments.first?.text ?? "" : transcript.fullText
        return text.prefix(80).description
    }

    // MARK: - Helpers

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

// MARK: - Transcript segment view with sync highlight

struct TranscriptSegmentsView: View {
    let segments: [Transcript.Segment]
    let currentTime: TimeInterval

    private var activeIndex: Int? {
        guard currentTime >= 0 else { return nil }
        return segments.lastIndex { $0.startTime <= currentTime }
    }

    // Build a single flowing Text from all segments, styling the active one distinctly
    private var flowingText: Text {
        segments.enumerated().reduce(Text("")) { result, item in
            let (index, segment) = item
            let part = Text(segment.text + " ")
                .foregroundColor(index == activeIndex ? .primary : .secondary)
                .fontWeight(index == activeIndex ? .semibold : .regular)
            return result + part
        }
    }

    var body: some View {
        ScrollView {
            flowingText
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 220)
    }
}

// MARK: - Playback bar

struct PlaybackBar: View {
    @EnvironmentObject var manager: RecordingManager

    private var progress: Double {
        guard manager.playbackDuration > 0 else { return 0 }
        return min(manager.playbackTime / manager.playbackDuration, 1.0)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.systemGray4)).frame(height: 3)
                Capsule().fill(Color.accentColor).frame(width: geo.size.width * progress, height: 3)
            }
        }
        .frame(height: 3)
    }
}
