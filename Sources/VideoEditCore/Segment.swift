import Foundation

public struct Segment: Sendable, Codable, Identifiable {
    public let id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var words: [WordTimestamp]

    public init(start: Double, end: Double, text: String, words: [WordTimestamp] = []) {
        self.id = UUID()
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

public struct WordTimestamp: Sendable, Codable {
    public let word: String
    public let start: Double
    public let end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}
