import Foundation

struct Recording: Identifiable, Codable {
    let id: UUID
    let filename: String
    var title: String
    let date: Date
    var duration: TimeInterval

    var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(filename)
    }

    var formattedDate: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }

    var formattedDuration: String {
        let m = Int(duration) / 60
        let s = Int(duration) % 60
        return String(format: "%d:%02d", m, s)
    }

    static func autoTitle(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mma"
        return f.string(from: date)
    }
}
