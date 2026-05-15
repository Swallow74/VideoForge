import Foundation

private let weakConnectives: Set<String> = [
    "e", "ma", "o", "oppure", "che", "perché", "perche", "quindi",
    "allora", "mentre", "invece", "comunque", "però", "pero",
    "dunque", "infatti", "cioè", "cioe", "inoltre",
    "anche", "poi", "tuttavia", "anzi",
]

private let strongStarts: Set<String> = [
    "no", "sì", "si", "ah", "oh", "beh", "ecco", "ok", "okay",
    "bene", "giusto", "certo",
]

private let pauseWords: Set<String> = [
    "diciamo", "praticamente", "fondamentalmente", "sostanzialmente",
]

public struct BoundaryContext: Sendable {
    public var prevGap: Double
    public var silenceAfter: Double

    public init(prevGap: Double = 0, silenceAfter: Double = 0) {
        self.prevGap = prevGap
        self.silenceAfter = silenceAfter
    }
}

public enum BoundaryScore {
    public static func evaluate(
        currText: String,
        currEnd: Double,
        nextText: String,
        nextStart: Double,
        profile: VideoProfile,
        context: BoundaryContext? = nil
    ) -> Float {
        let curr = currText.trimmingCharacters(in: .whitespaces)
        let nxt = nextText.trimmingCharacters(in: .whitespaces)

        guard !curr.isEmpty, !nxt.isEmpty else { return 1.0 }

        let gapSec = nextStart - currEnd
        var score: Float = 0

        let gap = Float(min(gapSec / profile.gapBreak, 1.5))
        score += gap * 0.25

        if curr.count > profile.maxChars {
            score += 0.4
        }

        let endsStrong = curr.last.map { ".!?…".contains($0) } ?? false
        let endsComma = curr.last.map { ",;:".contains($0) } ?? false

        if endsStrong {
            score += 0.7
        } else if endsComma {
            score -= 0.4
        }

        if let firstChar = nxt.first {
            if firstChar.isUppercase {
                score += 0.3
            } else {
                score -= 0.3
            }
        }

        let firstWord = nxt.split(separator: " ").first.map {
            $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "«»\"'"))
        } ?? ""

        if weakConnectives.contains(firstWord) {
            if !endsStrong {
                score -= 0.5 * profile.weakConjBoost
            }
        }
        if strongStarts.contains(firstWord) {
            score += 0.3
        }
        if pauseWords.contains(firstWord) {
            score -= 0.3
        }

        let currWords = curr.split(separator: " ").count
        let lenPenalty: Float
        if currWords <= 2 { lenPenalty = 0.5 }
        else if currWords <= 4 { lenPenalty = 0.2 }
        else { lenPenalty = 0 }

        if !endsStrong { score -= lenPenalty }

        if let ctx = context {
            if ctx.prevGap > 0 && gapSec < ctx.prevGap * 0.3 {
                score -= 0.2
            }
            if ctx.silenceAfter > 2.0 {
                score += 0.3
            }
        }

        return score
    }

    public static func shouldBreak(
        currText: String,
        currEnd: Double,
        nextText: String,
        nextStart: Double,
        profile: VideoProfile,
        context: BoundaryContext? = nil
    ) -> Bool {
        evaluate(
            currText: currText, currEnd: currEnd,
            nextText: nextText, nextStart: nextStart,
            profile: profile, context: context
        ) >= profile.boundaryThreshold
    }
}
