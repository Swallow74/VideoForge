import Foundation
import MLX
import MLXNN

public actor WhisperGenerator {
    private var model: WhisperModel?
    private var modelLoaded = false

    private let sotToken = 50257
    private let eotToken = 50256
    private let transcribeToken = 50359
    private let noTimestampsToken = 50363

    public let language: String

    public init(language: String = "it") {
        self.language = language
    }

    public func loadModel(modelSize: String = "large-v3") async throws {
        let config = WhisperConfig.forModel(modelSize)
        let whisper = WhisperModel(config: config)
        self.model = whisper
        self.modelLoaded = true
    }

    public func transcribe(audio: [Float], language: String? = nil) async throws -> WhisperResult {
        guard modelLoaded, let model = model else {
            throw WhisperError.modelNotLoaded
        }

        let lang = language ?? self.language

        var samples = audio
        WhisperAudio.padOrTruncate(&samples)
        let mel = WhisperAudio.computeMelSpectrogram(samples)
        let nFrames = mel.count / WhisperAudio.nMels
        let normalizedMel = WhisperAudio.normalizeMel(mel, nFrames: nFrames, nMel: WhisperAudio.nMels)

        let melArray = MLXArray(normalizedMel, [nFrames, WhisperAudio.nMels]).transposed(axes: [1, 0])
        let melInput = melArray.expandedDimensions(axis: 0)

        let encoderOutput = model.encode(melInput)

        let startTokens = [sotToken, WhisperLanguage(rawValue: lang)?.token ?? 50259, transcribeToken, noTimestampsToken]
        let generated = try await generate(model: model, encoderOutput: encoderOutput, promptTokens: startTokens)

        guard !generated.isEmpty else {
            return WhisperResult(segments: [], language: lang)
        }

        let textTokens = generated
        let text = decodeTokens(textTokens)

        let wordCount = max(text.split(separator: " ").count, 1)
        let segDuration = Double(wordCount) * 0.3
        let wordTimestamps = text.split(separator: " ").enumerated().map { i, word in
            WhisperWord(
                word: String(word),
                start: Double(i) * segDuration / Double(wordCount),
                end: Double(i + 1) * segDuration / Double(wordCount)
            )
        }

        let segment = WhisperSegment(
            start: 0,
            end: segDuration,
            text: text,
            words: wordTimestamps
        )

        return WhisperResult(segments: [segment], language: lang)
    }

    private func generate(
        model: WhisperModel,
        encoderOutput: MLXArray,
        promptTokens: [Int],
        maxTokens: Int = 224
    ) async throws -> [Int] {
        var generated = promptTokens

        for _ in 0..<maxTokens {
            let tokenArray = MLXArray(generated.map(Float.init), [1, generated.count])

            let logits = model.decode(tokenArray, encoderOutput: encoderOutput)
            let lastLogits = logits[0..., generated.count - 1, 0...]

            let logitsArray = lastLogits.asArray(Float.self)
            let suppressRange = 0..<50257
            var filtered = logitsArray
            for i in suppressRange where i < filtered.count {
                filtered[i] = -Float.greatestFiniteMagnitude
            }

            guard let nextToken = filtered.enumerated().max(by: { $0.element < $1.element })?.offset else {
                break
            }

            generated.append(nextToken)

            if nextToken == eotToken {
                break
            }
        }

        return Array(generated.dropFirst(promptTokens.count))
    }

    private func decodeTokens(_ tokens: [Int]) -> String {
        let words: [String] = tokens.compactMap { token in
            if token < 50257 {
                return "<token_\(token)>"
            }
            return nil
        }
        return words.joined(separator: " ")
    }
}

public enum WhisperError: Error {
    case modelNotLoaded
    case weightNotFound(String)
    case tokenizerError(String)
    case generationFailed(String)
}