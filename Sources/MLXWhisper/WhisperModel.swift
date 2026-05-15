import Foundation
import MLX
import MLXNN

// MARK: - Sinusoidal Position Embedding

func createSinusoidalPE(length: Int, dim: Int) -> MLXArray {
    var data = [Float](repeating: 0, count: length * dim)
    for pos in 0..<length {
        for i in 0..<dim {
            let freq = 1.0 / pow(10000.0, Float(2 * (i / 2)) / Float(dim))
            if i % 2 == 0 {
                data[pos * dim + i] = sin(Float(pos) * freq)
            } else {
                data[pos * dim + i] = cos(Float(pos) * freq)
            }
        }
    }
    return MLXArray(data, [length, dim])
}

// MARK: - Encoder Block

public class WhisperEncoderBlock: Module {
    @ModuleInfo public var attention: MultiHeadAttention
    @ModuleInfo public var attnNorm: LayerNorm
    @ModuleInfo public var mlpGate: Linear
    @ModuleInfo public var mlpDown: Linear
    @ModuleInfo public var mlpNorm: LayerNorm

    public init(dimensions: Int, numHeads: Int) {
        attention = MultiHeadAttention(dimensions: dimensions, numHeads: numHeads)
        attnNorm = LayerNorm(dimensions: dimensions)
        mlpGate = Linear(dimensions, dimensions * 4)
        mlpDown = Linear(dimensions * 4, dimensions)
        mlpNorm = LayerNorm(dimensions: dimensions)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = attnNorm(x)
        h = attention(h, keys: h, values: h)
        h = x + h

        var h2 = mlpNorm(h)
        h2 = gelu(mlpGate(h2))
        h2 = mlpDown(h2)
        return h + h2
    }
}

// MARK: - Encoder

public class WhisperEncoder: Module {
    @ModuleInfo public var conv1: Conv1d
    @ModuleInfo public var conv2: Conv1d
    public var positionalEmbedding: MLXArray
    @ModuleInfo public var blocks: [WhisperEncoderBlock]
    @ModuleInfo public var layerNorm: LayerNorm

    public init(dimensions: Int, numHeads: Int, numLayers: Int, maxPositions: Int = 1500) {
        conv1 = Conv1d(inputChannels: 80, outputChannels: dimensions, kernelSize: 3, padding: 1)
        conv2 = Conv1d(inputChannels: dimensions, outputChannels: dimensions, kernelSize: 3, stride: 2, padding: 1)
        positionalEmbedding = createSinusoidalPE(length: maxPositions, dim: dimensions)
        blocks = (0..<numLayers).map { _ in WhisperEncoderBlock(dimensions: dimensions, numHeads: numHeads) }
        layerNorm = LayerNorm(dimensions: dimensions)
    }

    public func callAsFunction(_ x: MLXArray) -> MLXArray {
        var h = x.transposed(axes: [0, 2, 1])
        h = gelu(conv1(h))
        h = gelu(conv2(h))
        let seqLen = h.dim(1)
        let dModel = h.dim(2)
        h = h + positionalEmbedding[0..<seqLen, 0..<dModel]
        for block in blocks { h = block(h) }
        return layerNorm(h)
    }
}

// MARK: - Decoder Block

public class WhisperDecoderBlock: Module {
    @ModuleInfo public var selfAttention: MultiHeadAttention
    @ModuleInfo public var selfAttNorm: LayerNorm
    @ModuleInfo public var crossAttention: MultiHeadAttention
    @ModuleInfo public var crossAttNorm: LayerNorm
    @ModuleInfo public var mlpGate: Linear
    @ModuleInfo public var mlpDown: Linear
    @ModuleInfo public var mlpNorm: LayerNorm

    public init(dimensions: Int, numHeads: Int) {
        selfAttention = MultiHeadAttention(dimensions: dimensions, numHeads: numHeads)
        selfAttNorm = LayerNorm(dimensions: dimensions)
        crossAttention = MultiHeadAttention(dimensions: dimensions, numHeads: numHeads)
        crossAttNorm = LayerNorm(dimensions: dimensions)
        mlpGate = Linear(dimensions, dimensions * 4)
        mlpDown = Linear(dimensions * 4, dimensions)
        mlpNorm = LayerNorm(dimensions: dimensions)
    }

    public func callAsFunction(_ x: MLXArray, encoderOutput: MLXArray, causalMask: MLXArray) -> MLXArray {
        var h = selfAttNorm(x)
        h = selfAttention(h, keys: h, values: h, mask: causalMask)
        h = x + h

        var h2 = crossAttNorm(h)
        h2 = crossAttention(h2, keys: encoderOutput, values: encoderOutput)
        h = h + h2

        var h3 = mlpNorm(h)
        h3 = gelu(mlpGate(h3))
        h3 = mlpDown(h3)
        return h + h3
    }
}

// MARK: - Decoder

public class WhisperDecoder: Module {
    @ModuleInfo public var tokenEmbedding: Embedding
    public var positionalEmbedding: MLXArray
    @ModuleInfo public var blocks: [WhisperDecoderBlock]
    @ModuleInfo public var layerNorm: LayerNorm
    @ModuleInfo public var outputProjection: Linear

    public init(vocabSize: Int, dimensions: Int, numHeads: Int, numLayers: Int, maxPositions: Int = 448) {
        tokenEmbedding = Embedding(embeddingCount: vocabSize, dimensions: dimensions)
        positionalEmbedding = createSinusoidalPE(length: maxPositions, dim: dimensions)
        blocks = (0..<numLayers).map { _ in WhisperDecoderBlock(dimensions: dimensions, numHeads: numHeads) }
        layerNorm = LayerNorm(dimensions: dimensions)
        outputProjection = Linear(dimensions, vocabSize, bias: false)
    }

    public func callAsFunction(_ tokens: MLXArray, encoderOutput: MLXArray) -> MLXArray {
        let seqLen = tokens.dim(1)
        let dModel = tokenEmbedding.weight.dim(1)
        var h = tokenEmbedding(tokens) + positionalEmbedding[0..<seqLen, 0..<dModel]
        let causalMask = MultiHeadAttention.createAdditiveCausalMask(seqLen)
        for block in blocks { h = block(h, encoderOutput: encoderOutput, causalMask: causalMask) }
        h = layerNorm(h)
        return outputProjection(h)
    }
}

// MARK: - Full Model

public class WhisperModel: Module {
    @ModuleInfo public var encoder: WhisperEncoder
    @ModuleInfo public var decoder: WhisperDecoder
    public let config: WhisperConfig

    public init(config: WhisperConfig) {
        self.config = config
        encoder = WhisperEncoder(dimensions: config.dimensions, numHeads: config.numHeads, numLayers: config.encoderLayers)
        decoder = WhisperDecoder(vocabSize: config.vocabSize, dimensions: config.dimensions, numHeads: config.numHeads, numLayers: config.decoderLayers)
    }

    public func encode(_ mel: MLXArray) -> MLXArray { encoder(mel) }
    public func decode(_ tokens: MLXArray, encoderOutput: MLXArray) -> MLXArray { decoder(tokens, encoderOutput: encoderOutput) }
}

// MARK: - Config

public struct WhisperConfig: Sendable {
    public let vocabSize: Int
    public let dimensions: Int
    public let numHeads: Int
    public let encoderLayers: Int
    public let decoderLayers: Int

    public static func forModel(_ size: String) -> WhisperConfig {
        switch size {
        case "large-v3", "large-v2":
            return WhisperConfig(vocabSize: 51866, dimensions: 1280, numHeads: 20, encoderLayers: 32, decoderLayers: 32)
        case "medium":
            return WhisperConfig(vocabSize: 51866, dimensions: 1024, numHeads: 16, encoderLayers: 24, decoderLayers: 24)
        case "small":
            return WhisperConfig(vocabSize: 51866, dimensions: 768, numHeads: 12, encoderLayers: 12, decoderLayers: 12)
        case "base":
            return WhisperConfig(vocabSize: 51866, dimensions: 512, numHeads: 8, encoderLayers: 6, decoderLayers: 6)
        case "tiny":
            return WhisperConfig(vocabSize: 51866, dimensions: 384, numHeads: 6, encoderLayers: 4, decoderLayers: 4)
        default: return .forModel("large-v3")
        }
    }
}