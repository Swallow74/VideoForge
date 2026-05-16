import Foundation

public enum AudioService {
    private static let ffmpegPaths = [
        "/opt/homebrew/bin/ffmpeg",
        "/usr/local/bin/ffmpeg",
        "/usr/bin/ffmpeg",
        "\(NSHomeDirectory())/.videoforge/bin/ffmpeg",
    ]

    private static let ffprobePaths = [
        "/opt/homebrew/bin/ffprobe",
        "/usr/local/bin/ffprobe",
        "/usr/bin/ffprobe",
        "\(NSHomeDirectory())/.videoforge/bin/ffprobe",
    ]

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

        guard let ffmpeg = firstExecutable(at: ffmpegPaths) else {
            throw NSError(domain: "AudioService", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "ffmpeg non trovato. Installalo con: brew install ffmpeg"])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-y", "-i", videoURL.path,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            outputURL.path
        ]

        let errorPipe = Pipe()
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
        guard let ffprobe = firstExecutable(at: ffprobePaths) else { return 0 }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
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

    // MARK: - Helpers

    private static func firstExecutable(at paths: [String]) -> String? {
        for path in paths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }
}
