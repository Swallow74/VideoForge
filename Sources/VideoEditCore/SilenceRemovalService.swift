import Foundation

/// Auto-detects and removes silence from audio/video.
/// Uses FFmpeg `silencedetect` + `aselect` filters.
public enum SilenceRemovalService {
    public struct Settings: Sendable {
        public let silenceThreshold: Float  // dB (e.g. -30)
        public let minSilenceDuration: Double  // seconds (e.g. 0.5)
        public let paddingBefore: Double  // seconds of audio to keep before speech
        public let paddingAfter: Double  // seconds of audio to keep after speech

        public init(
            silenceThreshold: Float = -30,
            minSilenceDuration: Double = 0.5,
            paddingBefore: Double = 0.1,
            paddingAfter: Double = 0.2
        ) {
            self.silenceThreshold = silenceThreshold
            self.minSilenceDuration = minSilenceDuration
            self.paddingBefore = paddingBefore
            self.paddingAfter = paddingAfter
        }

        public static let `default` = Settings()
    }

    /// Analyze audio and return non-silent segments as time ranges.
    public static func detectSilences(
        audioURL: URL,
        settings: Settings = .default
    ) async throws -> [(start: Double, end: Double)] {
        let process = Process()
        process.executableURL = findFFmpeg()
        process.arguments = [
            "-i", audioURL.path,
            "-af", "silencedetect=noise=\(settings.silenceThreshold)dB:d=\(settings.minSilenceDuration)",
            "-f", "null", "-"
        ]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errOutput = String(data: errData, encoding: .utf8) ?? ""

        return parseSilenceDetectOutput(errOutput, settings: settings)
    }

    /// Remove silences and produce a new audio/video file.
    public static func removeSilences(
        inputURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        let segments = try await detectSilences(audioURL: inputURL, settings: settings)
        guard !segments.isEmpty else {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return
        }

        // Build aselect filter to keep only speech segments
        let selectFilters = segments.enumerated().map { i, seg in
            "between(t,\(seg.start),\(seg.end))"
        }.joined(separator: "+")

        let process = Process()
        process.executableURL = findFFmpeg()
        process.arguments = [
            "-i", inputURL.path,
            "-af", "aselect='\(selectFilters)',asetpts=N/SR/TB",
            "-vn",  // audio only for now
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Silence removal failed")
        }
    }

    /// Remove silences from video (crops video to match audio).
    public static func removeSilencesFromVideo(
        inputURL: URL,
        outputURL: URL,
        settings: Settings = .default
    ) async throws {
        let segments = try await detectSilences(audioURL: inputURL, settings: settings)
        guard !segments.isEmpty else {
            try FileManager.default.copyItem(at: inputURL, to: outputURL)
            return
        }

        let selectFilters = segments.enumerated().map { i, seg in
            "between(t,\(seg.start),\(seg.end))"
        }.joined(separator: "+")

        let filter = "aselect='\(selectFilters)',asetpts=N/SR/TB;select='\(selectFilters)',setpts=N/FRAME_RATE/TB"

        let process = Process()
        process.executableURL = findFFmpeg()
        process.arguments = [
            "-i", inputURL.path,
            "-filter_complex", filter,
            "-y", outputURL.path
        ]

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw ServiceError.processFailed("Video silence removal failed")
        }
    }

    // MARK: - Private

    private static func parseSilenceDetectOutput(
        _ output: String,
        settings: Settings
    ) -> [(Double, Double)] {
        let lines = output.components(separatedBy: .newlines)
        var start: Double?
        var segments: [(Double, Double)] = []

        for line in lines {
            if line.contains("silence_start") {
                if let val = parseFloatAfter(line, "silence_start: ") {
                    if let s = start {
                        let end = val + settings.paddingAfter
                        segments.append((max(0, s - settings.paddingBefore), end))
                    }
                    start = nil
                }
            }
            if line.contains("silence_end") {
                if let val = parseFloatAfter(line, "silence_end: ") {
                    start = val
                }
            }
        }

        // If no silence detected, keep entire audio
        if segments.isEmpty {
            return [(0, Double.greatestFiniteMagnitude)]
        }

        // Merge overlapping segments
        return mergeRanges(segments.sorted { a, b in a.0 < b.0 })
    }

    private static func parseFloatAfter(_ line: String, _ prefix: String) -> Double? {
        guard let range = line.range(of: prefix) else { return nil }
        let rest = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return Double(rest.components(separatedBy: .whitespaces).first ?? "")
    }

    private static func mergeRanges(_ ranges: [(Double, Double)]) -> [(Double, Double)] {
        guard !ranges.isEmpty else { return [] }
        var merged: [(Double, Double)] = [ranges[0]]
        for r in ranges.dropFirst() {
            if r.0 <= merged.last!.1 {
                merged[merged.count - 1].1 = max(merged.last!.1, r.1)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    private static func findFFmpeg() -> URL {
        let candidates = ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]
        for c in candidates {
            if FileManager.default.fileExists(atPath: c) { return URL(fileURLWithPath: c) }
        }
        return URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
    }
}

public enum ServiceError: Error {
    case processFailed(String)
}