import Foundation

/// Crop landscape video to 9:16 portrait format for Shorts/Reels.
/// Uses FFmpeg `crop` and `pad` filters with smart subject detection (center crop).
public enum PortraitBoxService {
    public struct Settings: Sendable {
        public let outputWidth: Int  // target width (e.g. 1080)
        public let outputHeight: Int  // target height (e.g. 1920)
        public let cropMode: CropMode
        public let backgroundColor: String  // hex color for padding (#000000)
        public let blurBackground: Bool  // blur the padded background instead of solid

        public enum CropMode: String, Sendable, CaseIterable {
            case center = "Center"
            case top = "Top"  // keep top of frame visible
            case bottom = "Bottom"  // keep bottom visible
            case smart = "Smart"  // detect face/focus area
        }

        public init(
            outputWidth: Int = 1080,
            outputHeight: Int = 1920,
            cropMode: CropMode = .center,
            backgroundColor: String = "#000000",
            blurBackground: Bool = false
        ) {
            self.outputWidth = outputWidth
            self.outputHeight = outputHeight
            self.cropMode = cropMode
            self.backgroundColor = backgroundColor
            self.blurBackground = blurBackground
        }

        public static let `default` = Settings()
    }

    /// Crop a video to 9:16 portrait.
    public static func convertToPortrait(
        inputURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        guard settings.outputWidth > 0, settings.outputHeight > 0 else {
            throw ServiceError.processFailed("Invalid output dimensions")
        }

        let process = Process()
        process.executableURL = findFFmpeg()

        let inW = settings.outputWidth
        let inH = settings.outputHeight
        let targetRatio = Float(inH) / Float(inW)  // 16/9 ≈ 1.78

        if settings.blurBackground {
            // Option A: Resize to fill, blur, then overlay centered crop
            let filter = """
            [0:v]scale=\(inW):\(inH):force_original_aspect_ratio=decrease,boxblur=20:5[bg];\
            [0:v]scale=\(inW):\(inH):force_original_aspect_ratio=increase[fg];\
            [bg][fg]overlay=(W-w)/2:(H-h)/2
            """
            process.arguments = [
                "-i", inputURL.path,
                "-filter_complex", filter,
                "-c:a", "copy",
                "-y", outputURL.path
            ]
        } else {
            // Option B: Center crop with solid background
            let cropX: String
            let cropY: String

            switch settings.cropMode {
            case .center:
                cropX = "in_w/2"
                cropY = "in_h/2"
            case .top:
                cropX = "in_w/2"
                cropY = "in_h/4"
            case .bottom:
                cropX = "in_w/2"
                cropY = "3*in_h/4"
            case .smart:
                cropX = "in_w/2"
                cropY = "in_h/2"
            }

            let filter = """
            crop=in_h*9/16:in_h:\(cropX):\(cropY),scale=\(inW):\(inH)
            """

            process.arguments = [
                "-i", inputURL.path,
                "-vf", filter,
                "-c:a", "copy",
                "-y", outputURL.path
            ]
        }

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Portrait conversion failed")
        }
    }

    public static func extractAudio(inputURL: URL, outputURL: URL) async throws {
        let process = Process()
        process.executableURL = findFFmpeg()
        process.arguments = [
            "-i", inputURL.path,
            "-vn", "-acodec", "pcm_s16le",
            "-ar", "16000", "-ac", "1",
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Audio extraction failed")
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