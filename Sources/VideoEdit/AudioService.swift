import Foundation

public enum AudioService {
    private static let ffmpeg = Process()

    public static func isAudioFile(_ url: URL) -> Bool {
        ["mp3", "wav", "m4a", "aac", "ogg", "flac"].contains(url.pathExtension.lowercased())
    }

    public static func extractAudio(from videoURL: URL) throws -> URL {
        let outputURL = videoURL.deletingPathExtension().appendingPathExtension("_audio.wav")

        if FileManager.default.fileExists(atPath: outputURL.path) {
            let videoAttrs = try FileManager.default.attributesOfItem(atPath: videoURL.path)
            let audioAttrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
            if let videoDate = videoAttrs[.modificationDate] as? Date,
               let audioDate = audioAttrs[.modificationDate] as? Date,
               audioDate >= videoDate {
                return outputURL
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffmpeg")
        }
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ffmpeg")
        }

        process.arguments = [
            "-y", "-i", videoURL.path,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            outputURL.path
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
            throw NSError(domain: "AudioService", code: Int(process.terminationStatus),
                         userInfo: [NSLocalizedDescriptionKey: String(data: stderr, encoding: .utf8) ?? "ffmpeg error"])
        }

        return outputURL
    }

    public static func getDuration(_ url: URL) -> Double {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/local/bin/ffprobe")
        }
        if !FileManager.default.fileExists(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/ffprobe")
        }

        process.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", url.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe

        guard (try? process.run()) != nil else { return 0 }
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let durationStr = format["duration"] as? String,
              let duration = Double(durationStr) else {
            return 0
        }
        return duration
    }
}