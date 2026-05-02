import SwiftUI

@main
struct AudioRecorderApp: App {
    @StateObject private var recordingManager = RecordingManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
        }
    }
}
