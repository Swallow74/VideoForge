import Foundation

public enum MergeService {
    public static func mergeAndGroup(_ segments: [Segment], profile: VideoProfile = .conversational) -> [Segment] {
        var grouped: [Segment] = []
        var buffer: [Segment] = []

        for seg in segments {
            if isLoop(seg.text) { continue }

            guard !buffer.isEmpty else {
                buffer = [seg]
                continue
            }

            let combined = buffer.map(\.text).joined(separator: " ") + " " + seg.text
            let duration = seg.end - buffer[0].start

            if combined.count > profile.maxChars || duration > profile.maxDuration {
                grouped.append(makeEntry(buffer))
                buffer = [seg]
            } else {
                buffer.append(seg)
            }
        }

        if !buffer.isEmpty {
            grouped.append(makeEntry(buffer))
        }

        return grouped
    }

    private static func isLoop(_ text: String) -> Bool {
        let words = text.lowercased().split(separator: " ")
        guard words.count >= 4 else { return false }

        let unique = Set(words)
        if unique.count <= 2 { return true }

        if words.count >= 8 {
            for n in [2, 3, 4] {
                guard words.count >= n * 3 else { continue }
                let chunks = stride(from: 0, to: words.count, by: n).map {
                    Array(words[$0..<min($0 + n, words.count)])
                }
                if chunks.count >= 3 {
                    let chunkSet = Set(chunks.map { $0.map(String.init).joined(separator: " ") })
                    if chunkSet.count <= 1 { return true }
                }
            }
        }
        return false
    }

    private static func makeEntry(_ segs: [Segment]) -> Segment {
        Segment(
            start: segs[0].start,
            end: segs[segs.count - 1].end,
            text: segs.map(\.text).joined(separator: " ")
        )
    }
}