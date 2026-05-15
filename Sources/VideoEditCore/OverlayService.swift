import Foundation

/// Picture-in-Picture overlay compositing using FFmpeg.
/// Combines webcam/screen overlays with adjustable position and size.
public enum OverlayService {
    public struct Settings: Sendable {
        public let position: OverlayPosition
        public let overlayScale: Float  // 0-1, size of overlay relative to main
        public let overlayOpacity: Float  // 0-1 opacity
        public let cornerRadius: Int  // rounded corners (pixels)
        public let shadowEnabled: Bool

        public enum OverlayPosition: String, Sendable, CaseIterable {
            case topLeft = "Top Left"
            case topRight = "Top Right"
            case bottomLeft = "Bottom Left"
            case bottomRight = "Bottom Right"
        }

        public init(
            position: OverlayPosition = .bottomRight,
            overlayScale: Float = 0.25,
            overlayOpacity: Float = 1.0,
            cornerRadius: Int = 0,
            shadowEnabled: Bool = false
        ) {
            self.position = position
            self.overlayScale = overlayScale
            self.overlayOpacity = overlayOpacity
            self.cornerRadius = cornerRadius
            self.shadowEnabled = shadowEnabled
        }

        public static let `default` = Settings()
    }

    /// Overlay a smaller video (e.g., webcam) on top of a main video.
    /// - Parameters:
    ///   - mainVideoURL: background/fullscreen video
    ///   - overlayVideoURL: smaller video to overlay (e.g., webcam)
    ///   - outputURL: output composited video
    ///   - settings: overlay position, size, etc.
    public static func applyOverlay(
        mainVideoURL: URL,
        overlayVideoURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        let process = Process()
        process.executableURL = findFFmpeg()

        // Calculate overlay position
        let position = overlayPosition(settings.position)
        let scaleFilter = "scale=iw*\(settings.overlayScale):ih*\(settings.overlayScale)"

        var filter = """
        [1:v]\(scaleFilter),format=rgba,colorkey=0x000000:0.01:0.0\
        \(settings.cornerRadius > 0 ? ",drawbox=x=0:y=0:w=iw:h=ih:color=black@0:t=fill" : "")\
        [overlay];\
        [0:v][overlay]overlay=\(position.x):\(position.y):format=auto
        """

        if settings.shadowEnabled {
            filter = """
            [1:v]\(scaleFilter),format=rgba,\
            drawbox=x=5:y=5:w=iw:h=ih:color=black@0.3:t=fill[shadow];\
            [0:v][shadow]overlay=\(position.x):\(position.y):format=auto[bg];\
            [1:v]\(scaleFilter),format=rgba[overlay];\
            [bg][overlay]overlay=\(position.x):\(position.y):format=auto
            """
        }

        process.arguments = [
            "-i", mainVideoURL.path,
            "-i", overlayVideoURL.path,
            "-filter_complex", filter,
            "-c:a", "copy",
            "-shortest",
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Overlay failed")
        }
    }

    private static func overlayPosition(_ pos: Settings.OverlayPosition) -> (x: Int, y: Int) {
        switch pos {
        case .topLeft:     return (10, 10)
        case .topRight:    return (-10, 10)   // FFmpeg overlay: negative = from right
        case .bottomLeft:  return (10, -10)   // negative = from bottom
        case .bottomRight: return (-10, -10)
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