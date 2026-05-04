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
    private var audioEngine: AVAudioEngine?
    private var restartTimer: Timer?

    private var accumulatedText: String = ""
    private var cycleOffset: TimeInterval = 0
    private var cycleStart: Date = Date()
    private var accumulatedSegments: [Transcript.Segment] = []
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

    func stopLiveTranscription() -> String {
        isLiveTranscribing = false
        restartTimer?.invalidate()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        let final = liveText
        liveText = ""
        accumulatedText = ""
        accumulatedSegments = []
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

        // Fallback: save the SFSpeechRecognizer draft
        let fallback = Transcript(
            engine: .appleSFSpeech,
            segments: [],
            fullText: draftText
        )
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

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        recognitionRequest = request

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let offset = self.cycleOffset
                let partialSegments: [Transcript.Segment] = result.bestTranscription.segments.map { seg in
                    Transcript.Segment(
                        text: seg.substring,
                        startTime: seg.timestamp + offset,
                        duration: seg.duration,
                        confidence: Float(seg.confidence)
                    )
                }
                Task { @MainActor in
                    self.liveText = self.accumulatedText + result.bestTranscription.formattedString
                    if result.isFinal {
                        self.accumulatedText = self.liveText + " "
                        self.accumulatedSegments += partialSegments
                    }
                }
            }
        }

        do {
            try engine.start()
        } catch {
            print("AVAudioEngine failed to start: \(error)")
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
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
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
        var fullText = ""

        for result in results {
            for seg in result.segments {
                let start = TimeInterval(seg.start)
                let end   = TimeInterval(seg.end)
                segments.append(Transcript.Segment(
                    text: seg.text.trimmingCharacters(in: .whitespaces),
                    startTime: start,
                    duration: end - start,
                    confidence: Float(exp(Double(seg.avgLogprob ?? 0)))
                ))
                fullText += seg.text
            }
        }

        return Transcript(engine: .whisperKitSmall, segments: segments, fullText: fullText.trimmingCharacters(in: .whitespaces))
    }

    private func save(_ transcript: Transcript, for recording: Recording) {
        let url = Transcript.url(for: recording.filename)
        if let data = try? JSONEncoder().encode(transcript) {
            try? data.write(to: url)
        }
    }
}
