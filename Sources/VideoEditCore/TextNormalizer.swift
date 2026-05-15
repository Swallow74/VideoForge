import Foundation

public enum TextNormalizer {
    public static func normalizeText(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        t = t.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return t }
        t = t.prefix(1).uppercased() + t.dropFirst()
        t = t.replacingOccurrences(of: "\\s+([.,!?;:])", with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "([.!?])([A-Za-z])", with: "$1 $2", options: .regularExpression)
        return t
    }

    public static func fixPunctLocal(
        text: String,
        nextText: String = "",
        gapSec: Double = 1.0,
        profile: VideoProfile = .conversational,
        context: BoundaryContext? = nil
    ) -> String {
        var t = text.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return t }

        let brk: Bool
        if nextText.isEmpty {
            brk = true
        } else {
            brk = BoundaryScore.shouldBreak(
                currText: t, currEnd: 0,
                nextText: nextText, nextStart: gapSec,
                profile: profile, context: context
            )
        }

        if let first = t.first, first.isLowercase {
            t = String(first).uppercased() + t.dropFirst()
        }

        if brk {
            if let last = t.last, !".!?".contains(last) {
                t += "."
            }
        } else {
            if let last = t.last, ".!?".contains(last) {
                let wordCount = t.split(separator: " ").count
                if wordCount > 1 {
                    // pass - keep punctuation
                } else if wordCount <= 1 {
                    t = t.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
                    t = t.trimmingCharacters(in: .whitespaces)
                }
            }
        }

        return t
    }

    public static func needsQwen(_ text: String) -> Bool {
        guard text.count >= 30 else { return false }
        if text.contains("[") || text.contains("]") || text.contains("(") || text.contains(")") {
            return true
        }
        if text.components(separatedBy: "  ").count > 2 {
            return true
        }
        if text.range(of: "[a-z][A-Z]", options: .regularExpression) != nil {
            return true
        }
        let words = text.split(separator: " ")
        if words.count >= 3 {
            let unique = Set(words.map { $0.lowercased() })
            if unique.count <= 2 { return false }
        }
        return false
    }
}