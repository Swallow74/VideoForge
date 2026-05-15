import Foundation
import Accelerate

public enum WhisperAudio {
    public static let sampleRate = 16000
    public static let nFFT = 400
    public static let hopLength = 160
    public static let nMels = 80
    public static let chunkLengthSamples = 30 * sampleRate

    private static let melBasis: [Float] = {
        WhisperAudio.createMelFilterbank()
    }()

    public static func loadAndPreprocess(audioURL: URL) throws -> [Float] {
        let data = try Data(contentsOf: audioURL)
        let samples: [Float]

        if audioURL.pathExtension.lowercased() == "wav" {
            // WAV: skip header (44 bytes for standard PCM WAV)
            let wavData = data
            let headerSize = 44
            let audioData = wavData.dropFirst(headerSize)
            samples = audioData.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Int16.self)).map { Float($0) / Float(Int16.max) }
            }
        } else {
            // Assume raw float32 PCM
            samples = data.withUnsafeBytes { buffer in
                Array(buffer.bindMemory(to: Float.self))
            }
        }

        return samples
    }

    public static func computeMelSpectrogram(_ samples: [Float]) -> [Float] {
        let nSamples = samples.count
        let nFrames = max(1, (nSamples - nFFT) / hopLength + 1)

        var spectrogram = [Float](repeating: 0, count: nFrames * nFFT / 2)

        // Hann window
        var window = [Float](repeating: 0, count: nFFT)
        vDSP_hann_window(&window, vDSP_Length(nFFT), Int32(vDSP_HANN_NORM))

        for frame in 0..<nFrames {
            let start = frame * hopLength
            let end = min(start + nFFT, nSamples)
            let frameLen = end - start

            var padded = [Float](repeating: 0, count: nFFT)
            if frameLen > 0 {
                for i in 0..<frameLen {
                    padded[i] = samples[start + i] * window[i]
                }
            }

            var realPart = padded
            var imagPart = [Float](repeating: 0, count: nFFT)

            realPart.withUnsafeMutableBufferPointer { realBuf in
                imagPart.withUnsafeMutableBufferPointer { imagBuf in
                    var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)
                    let log2n = vDSP_Length(log2(Float(nFFT)))
                    guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
                        return
                    }
                    vDSP_fft_zip(fftSetup, &splitComplex, 1, log2n, FFTDirection(kFFTDirection_Forward))
                    vDSP_destroy_fftsetup(fftSetup)
                }
            }

            let halfN = nFFT / 2
            for i in 0..<halfN {
                let mag = sqrt(realPart[i] * realPart[i] + imagPart[i] * imagPart[i])
                spectrogram[frame * halfN + i] = mag
            }
        }

        // Apply Mel filterbank
        let nMelBins = nMels
        let melSpectrogram = applyMelFilterbank(spectrogram, nFrames: nFrames, nFreq: nFFT / 2, nMel: nMelBins)

        // Log
        var result = [Float](repeating: 0, count: melSpectrogram.count)
        for i in 0..<melSpectrogram.count {
            result[i] = log(max(melSpectrogram[i], 1e-10))
        }

        return result
    }

    private static func createMelFilterbank() -> [Float] {
        let nFreq = nFFT / 2
        let fMin: Float = 0
        let fMax: Float = 8000

        func melToHz(_ mel: Float) -> Float {
            700 * (pow(10, mel / 2595) - 1)
        }

        func hzToMel(_ hz: Float) -> Float {
            2595 * log10(1 + hz / 700)
        }

        let melMin = hzToMel(fMin)
        let melMax = hzToMel(fMax)
        let melStep = (melMax - melMin) / Float(nMels + 1)

        let bins = (0...nMels+1).map { melToMel(melMin + Float($0) * melStep) }
            .map { $0 * Float(nFreq) / fMax }

        var filterbank = [Float](repeating: 0, count: nMels * nFreq)

        for m in 0..<nMels {
            let fStart = bins[m]
            let fCenter = bins[m + 1]
            let fEnd = bins[m + 2]

            for f in 0..<nFreq {
                let freq = Float(f)
                if freq >= fStart && freq <= fCenter {
                    filterbank[m * nFreq + f] = (freq - fStart) / (fCenter - fStart)
                } else if freq >= fCenter && freq <= fEnd {
                    filterbank[m * nFreq + f] = (fEnd - freq) / (fEnd - fCenter)
                }
            }
        }

        return filterbank
    }

    private static func melToMel(_ mel: Float) -> Float {
        700 * (pow(10, mel / 2595) - 1)
    }

    private static func applyMelFilterbank(_ spectrogram: [Float], nFrames: Int, nFreq: Int, nMel: Int) -> [Float] {
        var result = [Float](repeating: 0, count: nFrames * nMel)

        for frame in 0..<nFrames {
            for m in 0..<nMel {
                var sum: Float = 0
                for f in 0..<nFreq {
                    sum += spectrogram[frame * nFreq + f] * melBasis[m * nFreq + f]
                }
                result[frame * nMel + m] = sum
            }
        }

        return result
    }

    public static func normalizeMel(_ mel: [Float], nFrames: Int, nMel: Int) -> [Float] {
        var result = mel
        for m in 0..<nMel {
            var sum: Float = 0
            var sumSq: Float = 0
            for f in 0..<nFrames {
                let val = mel[f * nMel + m]
                sum += val
                sumSq += val * val
            }
            let mean = sum / Float(nFrames)
            let variance = sumSq / Float(nFrames) - mean * mean
            let std = sqrt(max(variance, 1e-10))
            for f in 0..<nFrames {
                result[f * nMel + m] = (mel[f * nMel + m] - mean) / std
            }
        }
        return result
    }

    public static func padOrTruncate(_ samples: inout [Float], to targetSamples: Int = 30 * 16000) {
        if samples.count < targetSamples {
            samples.append(contentsOf: [Float](repeating: 0, count: targetSamples - samples.count))
        } else if samples.count > targetSamples {
            samples = Array(samples.prefix(targetSamples))
        }
    }
}