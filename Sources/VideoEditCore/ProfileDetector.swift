import Foundation

public enum ProfileDetector {
    public static func detectProfile(from segments: [Segment]) -> VideoProfile {
        guard !segments.isEmpty else { return .conversational }

        let sampleSize = min(30, segments.count)
        let sampleTexts = segments.prefix(sampleSize).map(\.text)
        let fullSample = sampleTexts.joined(separator: " ")
        let words = fullSample.split(separator: " ")

        guard !words.isEmpty else { return .conversational }

        let questionCount = fullSample.filter { $0 == "?" }.count
        let questionRatio = Float(questionCount) / Float(max(words.count, 1))
        let avgSegLen = sampleTexts.map(\.count).reduce(0, +) / max(sampleTexts.count, 1)
        let avgWordLen = words.map(\.count).reduce(0, +) / max(words.count, 1)
        let longSegCount = sampleTexts.filter { $0.count > 60 }.count
        let longSegRatio = Float(longSegCount) / Float(max(sampleTexts.count, 1))

        if questionRatio > 0.08 {
            return .conversational
        } else if longSegRatio > 0.5 && avgSegLen > 65 {
            return .lecturing
        } else if avgWordLen > 6 {
            return .technical
        }

        return .conversational
    }
}