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

    private var audioRecorder: AVAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var recordingTimer: Timer?
    private var playbackTimer: Timer?

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

            let filename = "recording_\(Date().timeIntervalSince1970).m4a"
            let url = documentsURL().appendingPathComponent(filename)

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()

            isRecording = true
            isPaused = false
            recordingTime = 0
            startRecordingTimer()
        } catch {
            print("Recording failed: \(error)")
        }
    }

    func pauseRecording() {
        audioRecorder?.pause()
        isPaused = true
        recordingTimer?.invalidate()
    }

    func resumeRecording() {
        audioRecorder?.record()
        isPaused = false
        startRecordingTimer()
    }

    func finishRecording() {
        guard let recorder = audioRecorder else { return }

        let url = recorder.url
        let duration = recorder.currentTime
        let now = Date()

        recorder.stop()
        recordingTimer?.invalidate()

        let recording = Recording(
            id: UUID(),
            filename: url.lastPathComponent,
            title: Recording.autoTitle(for: now),
            date: now,
            duration: duration
        )
        recordings.insert(recording, at: 0)
        saveRecordings()

        isRecording = false
        isPaused = false
        recordingTime = 0
        audioRecorder = nil
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
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }

    // MARK: - Private

    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            self?.recordingTime = self?.audioRecorder?.currentTime ?? 0
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
