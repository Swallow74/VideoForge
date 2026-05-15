import Foundation

/// Generate bilingual subtitles (dual language SRT).
/// Primary language from Whisper transcription, secondary via API or local model.
public enum DualLanguageService {
    public struct Settings: Sendable {
        public let primaryLanguage: String
        public let secondaryLanguage: String
        public let format: SubtitleFormat
        public let showTogether: Bool  // side-by-side or separate tracks

        public enum SubtitleFormat: String, Sendable, CaseIterable {
            case srt = "SRT"
            case vtt = "VTT"
            case ass = "ASS"
        }

        public init(
            primaryLanguage: String = "it",
            secondaryLanguage: String = "en",
            format: SubtitleFormat = .srt,
            showTogether: Bool = true
        ) {
            self.primaryLanguage = primaryLanguage
            self.secondaryLanguage = secondaryLanguage
            self.format = format
            self.showTogether = showTogether
        }

        public static let `default` = Settings()
    }

    /// Generate a dual-language SRT where each line shows both languages.
    public static func generateDualLanguageSRT(
        segments: [Segment],
        secondarySegments: [Segment],
        settings: Settings = .default
    ) -> String {
        var lines: [String] = []
        let maxSegments = max(segments.count, secondarySegments.count)

        for i in 0..<maxSegments {
            let primary = i < segments.count ? segments[i].text : ""
            let secondary = i < secondarySegments.count ? secondarySegments[i].text : ""
            let start = i < segments.count ? segments[i].start :
                (i < secondarySegments.count ? secondarySegments[i].start : 0)
            let end = i < segments.count ? segments[i].end :
                (i < secondarySegments.count ? secondarySegments[i].end : 0)

            lines.append("\(i + 1)")
            lines.append("\(formatTimestamp(start)) --> \(formatTimestamp(end))")

            if settings.showTogether && !primary.isEmpty && !secondary.isEmpty {
                lines.append(primary)
                lines.append(secondary)
            } else if settings.showTogether {
                lines.append(primary + secondary)
            } else {
                lines.append(primary)
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Generate separate VTT with two language tracks.
    public static func generateVTT(
        primarySegments: [Segment],
        secondarySegments: [Segment],
        primaryLabel: String = "Italiano",
        secondaryLabel: String = "English"
    ) -> String {
        var lines: [String] = []
        lines.append("WEBVTT")
        lines.append("Kind: captions")
        lines.append("")

        // Primary language track
        lines.append("NOTE \(primaryLabel)")
        for (i, seg) in primarySegments.enumerated() {
            lines.append("\(i + 1)")
            lines.append("\(formatTimestamp(seg.start)) --> \(formatTimestamp(seg.end))")
            lines.append(seg.text)
            lines.append("")
        }

        // Secondary language track
        lines.append("NOTE \(secondaryLabel)")
        for (i, seg) in secondarySegments.enumerated() {
            lines.append("\(i + 1 + primarySegments.count)")
            lines.append("\(formatTimestamp(seg.start)) --> \(formatTimestamp(seg.end))")
            lines.append(seg.text)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Translate segments to target language using omlx API.
    public static func translate(
        segments: [Segment],
        targetLanguage: String,
        apiURL: String = "http://127.0.0.1:8000/v1",
        model: String = ""
    ) async -> [Segment] {
        guard !model.isEmpty else {
            // Simple identity mapping if no model
            return segments.map { seg in
                Segment(start: seg.start, end: seg.end, text: "[\(targetLanguage)] \(seg.text)")
            }
        }

        var translated: [Segment] = []
        let batchSize = 5

        for i in stride(from: 0, to: segments.count, by: batchSize) {
            let batch = Array(segments[i..<min(i + batchSize, segments.count)])

            // Batch translate via API
            for seg in batch {
                let translatedText = await translateText(seg.text, target: targetLanguage, apiURL: apiURL, model: model)
                translated.append(Segment(
                    start: seg.start,
                    end: seg.end,
                    text: translatedText ?? seg.text
                ))
            }
        }

        return translated
    }

    private static func translateText(
        _ text: String,
        target: String,
        apiURL: String,
        model: String
    ) async -> String? {
        let prompt = "Traduci in \(target): \(text)"
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": "Sei un traduttore. Traduci SOLO il testo, senza spiegazioni."],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.0,
            "max_tokens": text.count * 3 + 30,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body),
              let url = URL(string: apiURL + "/chat/completions") else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func formatTimestamp(_ seconds: Double) -> String {
        let s = max(seconds, 0)
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let sec = Int(s) % 60
        let ms = min(Int(round((s - floor(s)) * 1000)), 999)
        return String(format: "%02d:%02d:%02d,%03d", h, m, sec, ms)
    }
}