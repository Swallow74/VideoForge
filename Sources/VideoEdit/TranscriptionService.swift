import Foundation
import VideoEditCore
import MLXWhisper

public enum TranscriptionError: Error {
    case modelNotFound(String)
    case transcriptionFailed(String)
    case cancelled
}

public enum TranscriptionService {
    private nonisolated(unsafe) static var generator: WhisperGenerator?

    public static func transcribe(
        audioURL: URL,
        modelSize: String = "large-v3",
        language: String? = nil,
        onProgress: (@Sendable (Double, Double, Double) -> Void)? = nil
    ) async throws -> [Segment] {
        let samples = try WhisperAudio.loadAndPreprocess(audioURL: audioURL)
        let langCode = language ?? "it"

        let gen: WhisperGenerator
        if let existing = generator {
            gen = existing
        } else {
            gen = WhisperGenerator(language: langCode)
            generator = gen
        }

        onProgress?(0.1, 0, 1)
        try await gen.loadModel(modelSize: modelSize)

        onProgress?(0.3, 0, 1)
        let result = try await gen.transcribe(audio: samples, language: langCode)

        onProgress?(1.0, 0, 1)
        return result.segments.map { seg in
            Segment(
                start: seg.start,
                end: seg.end,
                text: seg.text,
                words: seg.words.map { WordTimestamp(word: $0.word, start: $0.start, end: $0.end) }
            )
        }
    }
}