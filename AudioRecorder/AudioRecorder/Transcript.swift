import Foundation

struct Transcript: Codable {
    var version: Int = 1
    var language: String = "en-US"
    var engine: Engine = .whisperKitSmall
    var segments: [Segment] = []
    var fullText: String = ""

    enum Engine: String, Codable {
        case whisperKitSmall = "whisperkit-small"
        case appleSFSpeech   = "apple-sfspeech"
    }

    struct Segment: Codable, Identifiable {
        var id: UUID = UUID()
        var text: String
        var startTime: TimeInterval
        var duration: TimeInterval
        var confidence: Float
        var speaker: String? = nil

        var endTime: TimeInterval { startTime + duration }
    }

    static func filename(for recordingFilename: String) -> String {
        let base = (recordingFilename as NSString).deletingPathExtension
        return "\(base).json"
    }

    static func url(for recordingFilename: String) -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(filename(for: recordingFilename))
    }
}
