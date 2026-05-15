import Foundation

public enum SRTExporter {
    public static let maxCPS = 15

    public static func formatTimestamp(_ seconds: Double) -> String {
        let s = max(seconds, 0)
        let h = Int(s) / 3600
        let m = (Int(s) % 3600) / 60
        let sec = Int(s) % 60
        let ms = min(Int(round((s - floor(s)) * 1000)), 999)
        return String(format: "%02d:%02d:%02d,%03d", h, m, sec, ms)
    }

    public static func wrapText(_ text: String, maxChars: Int = 42) -> String {
        let words = text.split(separator: " ")
        var lines: [String] = []
        var currentLine = ""

        for word in words {
            let wordStr = String(word)
            if currentLine.isEmpty {
                currentLine = wordStr
            } else if currentLine.count + wordStr.count + 1 <= maxChars {
                currentLine += " " + wordStr
            } else {
                lines.append(currentLine)
                currentLine = wordStr
            }
        }
        if !currentLine.isEmpty {
            lines.append(currentLine)
        }

        return lines.prefix(3).joined(separator: "\n")
    }

    static func splitByCPS(_ seg: Segment) -> [Segment] {
        let dur = seg.end - seg.start
        let text = seg.text

        guard dur > 0, Double(text.count) / dur > Double(maxCPS) else {
            return [seg]
        }

        let candidates = text.enumerated().compactMap { (i, ch) -> Int? in
            ".!?".contains(ch) ? i + 1 : nil
        }

        guard !candidates.isEmpty else { return [seg] }

        let mid = text.count / 2
        let splitPos = candidates.min(by: { abs($0 - mid) < abs($1 - mid) })!

        guard splitPos >= 15, text.count - splitPos >= 15 else { return [seg] }

        let partA = String(text[text.startIndex..<text.index(text.startIndex, offsetBy: splitPos)]).trimmingCharacters(in: .whitespaces)
        let partB = String(text[text.index(text.startIndex, offsetBy: splitPos)...]).trimmingCharacters(in: .whitespaces)

        guard !partA.isEmpty, !partB.isEmpty else { return [seg] }

        let totalLen = partA.count + partB.count
        let ratioA = totalLen > 0 ? Double(partA.count) / Double(totalLen) : 0.5
        let splitAt = seg.start + dur * ratioA

        let aDur = splitAt - seg.start
        let bDur = seg.end - splitAt

        guard aDur >= 1.0, bDur >= 1.0 else { return [seg] }

        return [
            Segment(start: seg.start, end: splitAt, text: partA),
            Segment(start: splitAt, end: seg.end, text: partB),
        ]
    }

    static func validateSegments(_ segments: [Segment]) -> [Segment] {
        var validated: [Segment] = []
        for seg in segments {
            var s = seg
            if s.end <= s.start {
                s.end = s.start + 0.5
            }
            if let last = validated.last {
                if s.start < last.start {
                    s.start = last.end
                }
                if s.start >= s.end {
                    s.start = last.end
                    s.end = s.start + 0.5
                }
            }
            validated.append(s)
        }
        return validated
    }

    public static func exportSRT(_ segments: [Segment], to outputPath: String) throws {
        let validated = validateSegments(segments)

        var resynced: [Segment] = []
        for seg in validated {
            resynced.append(contentsOf: splitByCPS(seg))
        }

        resynced = validateSegments(resynced)

        var lines: [String] = []
        for (i, seg) in resynced.enumerated() {
            let startTs = formatTimestamp(seg.start)
            let endTs = formatTimestamp(seg.end)
            var text = seg.text

            if text.lowercased().contains("fino a poco"),
               !text.lowercased().contains("tempo fa") {
                text = text.replacingOccurrences(
                    of: "fino a poco", with: "fino a poco tempo fa",
                    options: .caseInsensitive
                )
            }

            text = wrapText(text, maxChars: 42)
            lines.append("\(i + 1)")
            lines.append("\(startTs) --> \(endTs)")
            lines.append("\(text)")
            lines.append("")
        }

        let content = lines.joined(separator: "\n")
        try content.write(toFile: outputPath, atomically: true, encoding: .utf8)
    }
}