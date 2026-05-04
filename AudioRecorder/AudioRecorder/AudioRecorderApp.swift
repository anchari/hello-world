import SwiftUI

@main
struct AudioRecorderApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var transcriptionManager = TranscriptionManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(transcriptionManager)
        }
    }
}
