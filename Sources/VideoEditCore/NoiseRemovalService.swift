import Foundation

/// Background noise removal via FFmpeg `anlmdn` filter.
public enum NoiseRemovalService {
    public struct Settings: Sendable {
        public let strength: Float  // noise reduction strength (0-1)
        public let voicePreserve: Bool  // preserve voice frequencies

        public init(strength: Float = 0.5, voicePreserve: Bool = true) {
            self.strength = strength
            self.voicePreserve = voicePreserve
        }

        public static let `default` = Settings()
    }

    /// Remove background noise from audio file.
    public static func removeNoise(
        inputURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        let process = Process()
        process.executableURL = findFFmpeg()

        // anlmdn: Non-local Means Denoising
        // s=strength, p=patch radius, r=search radius
        let anlmdnParams = "anlmdn=s=\(settings.strength):p=3:r=5:m=15"

        if settings.voicePreserve {
            // Highpass at 80Hz to preserve voice, then denoise
            process.arguments = [
                "-i", inputURL.path,
                "-af", "highpass=f=80,\(anlmdnParams)",
                "-y", outputURL.path
            ]
        } else {
            process.arguments = [
                "-i", inputURL.path,
                "-af", anlmdnParams,
                "-y", outputURL.path
            ]
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Noise removal failed")
        }
    }

    /// Remove noise from video (audio track only).
    public static func removeNoiseFromVideo(
        inputURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        let process = Process()
        process.executableURL = findFFmpeg()

        let filter = "highpass=f=80,anlmdn=s=\(settings.strength):p=3:r=5:m=15"

        process.arguments = [
            "-i", inputURL.path,
            "-af", filter,
            "-c:v", "copy",
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Video noise removal failed")
        }
    }

    private static func findFFmpeg() -> URL {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return URL(fileURLWithPath: c) }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
}