import Foundation

/// Add background music with auto-ducking (volume lowers when speech is detected).
/// Uses FFmpeg sidechaincompress filter for smooth ducking.
public enum MusicDuckingService {
    public struct Settings: Sendable {
        public let musicVolume: Float  // background music volume (0-1)
        public let duckLevel: Float  // how much to reduce music during speech (0=silent, 1=no duck)
        public let attackTime: Double  // how fast ducking kicks in (seconds)
        public let releaseTime: Double  // how fast ducking releases (seconds)
        public let threshold: Float  // speech detection threshold (dB)

        public init(
            musicVolume: Float = 0.3,
            duckLevel: Float = 0.15,
            attackTime: Double = 0.05,
            releaseTime: Double = 0.3,
            threshold: Float = -20
        ) {
            self.musicVolume = musicVolume
            self.duckLevel = duckLevel
            self.attackTime = attackTime
            self.releaseTime = releaseTime
            self.threshold = threshold
        }

        public static let `default` = Settings()
    }

    /// Mix background music with speech track, with auto-ducking.
    /// - Parameters:
    ///   - speechURL: video or audio with speech (main track)
    ///   - musicURL: background music file
    ///   - outputURL: output file with mixed audio
    ///   - settings: ducking parameters
    ///   - loopMusic: if true, loop music to match speech duration
    public static func addMusicWithDucking(
        speechURL: URL,
        musicURL: URL,
        outputURL: URL,
        settings: Settings = .default,
        loopMusic: Bool = true
    ) async throws {
        let process = Process()
        process.executableURL = findFFmpeg()

        // sidechaincompress: lowers music volume when speech is above threshold
        // threshold=dB, attack/release in ms, ratio=how much compression
        let filter: String
        if loopMusic {
            filter = """
            [1:a]aloop=loop=-1:size=2e9,volume=\(settings.musicVolume)[music];\
            [0:a][music]sidechaincompress=threshold=\(settings.threshold)dB:\
            ratio=4:attack=\(Int(settings.attackTime * 1000)):\
            release=\(Int(settings.releaseTime * 1000)):\
            makeup=1:level_sc=\(settings.duckLevel)[mixed]
            """
        } else {
            filter = """
            [1:a]volume=\(settings.musicVolume)[music];\
            [0:a][music]sidechaincompress=threshold=\(settings.threshold)dB:\
            ratio=4:attack=\(Int(settings.attackTime * 1000)):\
            release=\(Int(settings.releaseTime * 1000)):\
            makeup=1:level_sc=\(settings.duckLevel)[mixed]
            """
        }

        process.arguments = [
            "-i", speechURL.path,
            "-i", musicURL.path,
            "-filter_complex", filter,
            "-map", "[mixed]",
            "-map", "0:v?",  // copy video from speech track if present
            "-c:v", "copy",
            "-shortest",
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Music ducking failed")
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