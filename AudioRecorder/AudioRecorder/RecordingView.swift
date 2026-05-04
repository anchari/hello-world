import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var manager: RecordingManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                timerDisplay
                Spacer()
                controls
                    .padding(.bottom, 64)
            }
            .navigationTitle("Record")
        }
    }

    private var timerDisplay: some View {
        Text(formatTime(manager.recordingTime))
            .font(.system(size: 72, weight: .thin, design: .monospaced))
            .foregroundStyle(manager.isRecording && !manager.isPaused ? .red : .secondary)
            .contentTransition(.numericText())
            .animation(.linear(duration: 0.05), value: manager.recordingTime)
    }

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

                circleButton(
                    icon: "checkmark",
                    background: .green,
                    foreground: .white,
                    size: 76
                ) {
                    manager.finishRecording()
                }
            }
        } else {
            circleButton(
                icon: "mic.fill",
                background: .red,
                foreground: .white,
                size: 100
            ) {
                manager.startRecording()
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

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
