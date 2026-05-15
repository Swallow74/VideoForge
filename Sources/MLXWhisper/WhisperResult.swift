import Foundation

public struct WhisperWord: Sendable, Codable {
    public let word: String
    public let start: Double
    public let end: Double

    public init(word: String, start: Double, end: Double) {
        self.word = word
        self.start = start
        self.end = end
    }
}

public struct WhisperSegment: Sendable, Codable {
    public let start: Double
    public let end: Double
    public let text: String
    public let words: [WhisperWord]

    public init(start: Double, end: Double, text: String, words: [WhisperWord] = []) {
        self.start = start
        self.end = end
        self.text = text
        self.words = words
    }
}

public struct WhisperResult: Sendable {
    public let segments: [WhisperSegment]
    public let language: String

    public init(segments: [WhisperSegment], language: String) {
        self.segments = segments
        self.language = language
    }
}

public enum WhisperLanguage: String, CaseIterable {
    case it, en, fr, de, es, pt, ru, ja, zh

    public var token: Int {
        switch self {
        case .it: return 50259
        case .en: return 50259
        case .fr: return 50262
        case .de: return 50261
        case .es: return 50263
        case .pt: return 50264
        case .ru: return 50265
        case .ja: return 50266
        case .zh: return 50267
        }
    }
}