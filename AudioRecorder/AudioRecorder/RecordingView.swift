import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var manager: RecordingManager
    @EnvironmentObject var transcriptionManager: TranscriptionManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                timerDisplay
                    .padding(.top, 48)

                if manager.isRecording {
                    liveTranscriptArea
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                modelStateNote
                    .padding(.bottom, 8)

                controls
                    .padding(.bottom, 64)
            }
            .animation(.easeInOut(duration: 0.3), value: manager.isRecording)
            .navigationTitle("Record")
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Text(appVersion)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Timer

    private var timerDisplay: some View {
        Text(formatTime(manager.recordingTime))
            .font(.system(size: 72, weight: .thin, design: .monospaced))
            .foregroundStyle(manager.isRecording && !manager.isPaused ? .red : .secondary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.05), value: manager.recordingTime)
    }

    // MARK: - Live transcript

    private var liveTranscriptArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LIVE TRANSCRIPT")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            ScrollViewReader { proxy in
                ScrollView {
                    Text(transcriptionManager.liveText.isEmpty ? "Listening…" : transcriptionManager.liveText)
                        .font(.body)
                        .foregroundStyle(transcriptionManager.liveText.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .id("bottom")
                }
                .frame(height: 180)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)
                .onChange(of: transcriptionManager.liveText) { _, _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
        .padding(.top, 24)
    }

    // MARK: - Model state note

    @ViewBuilder
    private var modelStateNote: some View {
        switch transcriptionManager.modelState {
        case .loading(let progress):
            HStack(spacing: 8) {
                ProgressView(value: progress > 0 ? progress : nil)
                    .frame(width: 80)
                Text("Downloading transcription model…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .failed:
            Text("Transcription unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        if manager.isRecording {
            HStack(spacing: 52) {
                circleButton(
                    icon: manager.isPaused ? "play.fill" : "pause.fill",
                    background: Color(.systemGray5),
                    foreground: .primary,
                    size: 76
                ) {
                    if manager.isPaused {
                        manager.resumeRecording()
                    } else {
                        manager.pauseRecording()
                    }
                }

                circleButton(icon: "checkmark", background: .green, foreground: .white, size: 76) {
                    let draft = transcriptionManager.stopLiveTranscription()
                    manager.finishRecording(draftTranscript: draft)
                }
            }
        } else {
            circleButton(icon: "mic.fill", background: .red, foreground: .white, size: 100) {
                manager.startRecording()
                transcriptionManager.startLiveTranscription()
            }
            .shadow(color: .red.opacity(0.4), radius: 16, y: 8)
        }
    }

    private func circleButton(
        icon: String,
        background: Color,
        foreground: Color,
        size: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Circle()
                .fill(background)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: size * 0.38, weight: .medium))
                        .foregroundStyle(foreground)
                }
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
