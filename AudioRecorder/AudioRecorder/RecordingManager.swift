import AVFoundation

class RecordingManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isPaused = false
    @Published var recordingTime: TimeInterval = 0
    @Published var recordings: [Recording] = []

    @Published var playingID: UUID? = nil
    @Published var isPlaybackPaused = false
    @Published var playbackTime: TimeInterval = 0
    @Published var playbackDuration: TimeInterval = 0

    weak var transcriptionManager: TranscriptionManager?

    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?
    private var currentRecordingURL: URL?
    private var lastResumeTime: Date?
    private var accumulatedRecordingTime: TimeInterval = 0

    override init() {
        super.init()
        loadRecordings()
    }

    // MARK: - Recording

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)

            let engine = AVAudioEngine()
            audioEngine = engine
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            let filename = "recording_\(Date().timeIntervalSince1970).caf"
            let url = documentsURL().appendingPathComponent(filename)
            currentRecordingURL = url

            audioFile = try AVAudioFile(forWriting: url, settings: format.settings)

            inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
                guard let self, !self.isPaused else { return }
                try? self.audioFile?.write(from: buffer)
                self.transcriptionManager?.appendBuffer(buffer)
            }

            try engine.start()

            isRecording = true
            isPaused = false
            accumulatedRecordingTime = 0
            lastResumeTime = Date()
            recordingTime = 0
            startRecordingTimer()
        } catch {
            print("Recording failed: \(error)")
        }
    }

    func pauseRecording() {
        if let start = lastResumeTime {
            accumulatedRecordingTime += Date().timeIntervalSince(start)
        }
        lastResumeTime = nil
        isPaused = true
        recordingTimer?.invalidate()
    }

    func resumeRecording() {
        lastResumeTime = Date()
        isPaused = false
        startRecordingTimer()
    }

    func finishRecording(draftTranscript: String = "") {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioFile = nil
        recordingTimer?.invalidate()

        if let start = lastResumeTime {
            accumulatedRecordingTime += Date().timeIntervalSince(start)
        }
        let duration = accumulatedRecordingTime
        let now = Date()

        guard let cafURL = currentRecordingURL else {
            isRecording = false
            isPaused = false
            recordingTime = 0
            audioEngine = nil
            return
        }

        isRecording = false
        isPaused = false
        recordingTime = 0
        audioEngine = nil
        currentRecordingURL = nil
        lastResumeTime = nil
        accumulatedRecordingTime = 0

        let m4aFilename = cafURL.deletingPathExtension().appendingPathExtension("m4a").lastPathComponent
        let m4aURL = documentsURL().appendingPathComponent(m4aFilename)

        let recording = Recording(
            id: UUID(),
            filename: m4aFilename,
            title: Recording.autoTitle(for: now),
            date: now,
            duration: duration
        )
        recordings.insert(recording, at: 0)
        saveRecordings()

        Task {
            await convertToM4A(from: cafURL, to: m4aURL)
            try? FileManager.default.removeItem(at: cafURL)

            if let tm = transcriptionManager {
                await tm.transcribeRecording(recording, draftText: draftTranscript)
                if let i = self.recordings.firstIndex(where: { $0.id == recording.id }) {
                    await MainActor.run {
                        self.recordings[i].hasTranscript = true
                        self.saveRecordings()
                    }
                }
            }
        }
    }

    private func convertToM4A(from source: URL, to destination: URL) async {
        await withCheckedContinuation { continuation in
            guard let exportSession = AVAssetExportSession(
                asset: AVAsset(url: source),
                presetName: AVAssetExportPresetAppleM4A
            ) else {
                continuation.resume()
                return
            }
            exportSession.outputURL = destination
            exportSession.outputFileType = .m4a
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }
    }

    // MARK: - Playback

    func play(_ recording: Recording) {
        stopPlayback()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)

            audioPlayer = try AVAudioPlayer(contentsOf: recording.url)
            audioPlayer?.delegate = self
            audioPlayer?.play()

            playingID = recording.id
            isPlaybackPaused = false
            playbackTime = 0
            playbackDuration = audioPlayer?.duration ?? recording.duration
            startPlaybackTimer()
        } catch {
            print("Playback failed: \(error)")
        }
    }

    func pausePlayback() {
        audioPlayer?.pause()
        playbackTimer?.invalidate()
        isPlaybackPaused = true
    }

    func resumePlayback() {
        audioPlayer?.play()
        isPlaybackPaused = false
        startPlaybackTimer()
    }

    func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        playbackTimer?.invalidate()
        playingID = nil
        isPlaybackPaused = false
        playbackTime = 0
    }

    func skip(by seconds: TimeInterval) {
        guard let player = audioPlayer else { return }
        let newTime = max(0, min(player.currentTime + seconds, player.duration))
        player.currentTime = newTime
        playbackTime = newTime
    }

    // MARK: - CRUD

    func updateTitle(for id: UUID, title: String) {
        guard let i = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[i].title = title
        saveRecordings()
    }

    func delete(_ recording: Recording) {
        if playingID == recording.id { stopPlayback() }
        try? FileManager.default.removeItem(at: recording.url)
        let transcriptURL = Transcript.url(for: recording.filename)
        try? FileManager.default.removeItem(at: transcriptURL)
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }

    // MARK: - Private

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let start = self.lastResumeTime else { return }
            self.recordingTime = self.accumulatedRecordingTime + Date().timeIntervalSince(start)
        }
    }

    private func startPlaybackTimer() {
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.playbackTime = self?.audioPlayer?.currentTime ?? 0
        }
    }

    private func documentsURL() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func saveRecordings() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: "recordings")
        }
    }

    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: "recordings"),
              let decoded = try? JSONDecoder().decode([Recording].self, from: data) else { return }
        recordings = decoded
    }
}

extension RecordingManager: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playbackTimer?.invalidate()
        playingID = nil
        isPlaybackPaused = false
        playbackTime = 0
    }
}
