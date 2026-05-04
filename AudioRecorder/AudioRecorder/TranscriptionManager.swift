import AVFoundation
import Speech
import WhisperKit

@MainActor
class TranscriptionManager: ObservableObject {

    // MARK: - Published state

    @Published var liveText: String = ""
    @Published var modelState: ModelState = .notLoaded
    @Published var transcribingIDs: Set<UUID> = []

    enum ModelState: Equatable {
        case notLoaded
        case loading(Double)
        case ready
        case failed(String)
    }

    // MARK: - Private: live transcription

    private var recognizer: SFSpeechRecognizer?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var restartTimer: Timer?

    private var accumulatedText: String = ""
    private var cycleOffset: TimeInterval = 0
    private var cycleStart: Date = Date()
    private var isLiveTranscribing = false

    // MARK: - Private: WhisperKit

    private var whisper: WhisperKit?

    // MARK: - Init

    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        Task { await loadWhisperKit() }
    }

    // MARK: - Live transcription

    func startLiveTranscription() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else { return }
            DispatchQueue.main.async { self?.beginCycle() }
        }
    }

    // Called by RecordingManager's audio tap
    func appendBuffer(_ buffer: AVAudioPCMBuffer) {
        recognitionRequest?.append(buffer)
    }

    func stopLiveTranscription() -> String {
        isLiveTranscribing = false
        restartTimer?.invalidate()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        let final = liveText
        liveText = ""
        accumulatedText = ""
        cycleOffset = 0
        return final
    }

    // MARK: - Post-recording WhisperKit transcription

    func transcribeRecording(_ recording: Recording, draftText: String) async {
        await MainActor.run { transcribingIDs.insert(recording.id) }
        defer { Task { @MainActor in transcribingIDs.remove(recording.id) } }

        if case .ready = modelState, let whisper {
            do {
                let transcript = try await runWhisperKit(whisper, on: recording)
                save(transcript, for: recording)
                return
            } catch {
                print("WhisperKit failed: \(error) — falling back to SFSpeech draft")
            }
        }

        let fallback = Transcript(engine: .appleSFSpeech, segments: [], fullText: draftText)
        save(fallback, for: recording)
    }

    func loadTranscript(for recording: Recording) -> Transcript? {
        let url = Transcript.url(for: recording.filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Transcript.self, from: data)
    }

    // MARK: - Private: recognition cycle

    private func beginCycle() {
        isLiveTranscribing = true
        cycleStart = Date()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let offset = self.cycleOffset
                Task { @MainActor in
                    self.liveText = self.accumulatedText + result.bestTranscription.formattedString
                    if result.isFinal {
                        self.accumulatedText = self.liveText + " "
                    }
                }
                _ = offset // used for future segment timestamp tracking
            }
        }

        scheduleRestart()
    }

    private func scheduleRestart() {
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            self?.restartCycle()
        }
    }

    private func restartCycle() {
        guard isLiveTranscribing else { return }

        cycleOffset += Date().timeIntervalSince(cycleStart)
        accumulatedText = liveText + " "

        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        beginCycle()
    }

    // MARK: - Private: WhisperKit

    private func loadWhisperKit() async {
        await MainActor.run { modelState = .loading(0) }
        do {
            let kit = try await WhisperKit(model: "openai_whisper-small")
            await MainActor.run {
                self.whisper = kit
                self.modelState = .ready
            }
        } catch {
            await MainActor.run { self.modelState = .failed(error.localizedDescription) }
        }
    }

    private func runWhisperKit(_ kit: WhisperKit, on recording: Recording) async throws -> Transcript {
        let results = try await kit.transcribe(
            audioPath: recording.url.path,
            decodeOptions: DecodingOptions(task: .transcribe, language: "en")
        )

        var segments: [Transcript.Segment] = []
        var words: [String] = []

        for result in results {
            for seg in result.segments {
                let clean = Self.cleanSegmentText(seg.text)
                guard !clean.isEmpty else { continue }
                let start = TimeInterval(seg.start)
                let end   = TimeInterval(seg.end)
                segments.append(Transcript.Segment(
                    text: clean,
                    startTime: start,
                    duration: end - start,
                    confidence: Float(exp(Double(seg.avgLogprob ?? 0)))
                ))
                words.append(clean)
            }
        }

        return Transcript(engine: .whisperKitSmall, segments: segments, fullText: words.joined(separator: " "))
    }

    private static func cleanSegmentText(_ text: String) -> String {
        let pattern = #"\s*\[\d+:\d+\.\d+\s*-->\s*\d+:\d+\.\d+\]\s*"#
        let cleaned = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func save(_ transcript: Transcript, for recording: Recording) {
        let url = Transcript.url(for: recording.filename)
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: url)
        }
    }
}
