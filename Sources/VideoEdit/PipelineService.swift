import Foundation
import SwiftUI
import UniformTypeIdentifiers
import VideoEditCore

@Observable
@MainActor
final class PipelineService {
    // MARK: - Files
    var files: [URL] = []
    var isProcessing = false
    var progress: Double = 0
    var statusText = ""
    var log = ""

    // MARK: - Transcription
    var asrModel = "large-v3"
    var language = "it"
    var textModel = ""
    var profileName = "auto"
    var availableTextModels: [String] = []

    // MARK: - Silence Removal
    var enableSilenceRemoval = false
    var silenceThreshold: Float = -30
    var minSilenceDuration: Double = 0.5

    // MARK: - Noise Removal
    var enableNoiseRemoval = false
    var noiseStrength: Float = 0.5

    // MARK: - Portrait Box
    var enablePortraitBox = false
    var portraitWidth = 1080
    var portraitHeight = 1920
    var portraitCropMode = "Center"
    var portraitBlurBackground = false

    // MARK: - Music + Ducking
    var enableMusicDucking = false
    var musicURL: URL? = nil
    var musicVolume: Float = 0.3
    var duckLevel: Float = 0.15

    // MARK: - Dual Language
    var enableDualLanguage = false
    var secondaryLanguage = "en"
    var translationModel = ""

    // MARK: - Overlay
    var enableOverlay = false
    var overlayVideoURL: URL? = nil
    var overlayPosition = "Bottom Right"
    var overlayScale: Float = 0.25

    // MARK: - Teleprompter
    var teleprompterService = TeleprompterService()

    // MARK: - API Configuration
    var apiBaseURL = "http://127.0.0.1:8000"
    var grammarService: GrammarService {
        GrammarService(baseURL: apiBaseURL)
    }

    static let availableModels = ["large-v3", "large-v2", "medium", "small", "base", "tiny"]

    private var isCancelled = false
    private var processingTask: Task<Void, Never>? = nil

    // MARK: - Actions

    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .audio,
            UTType(filenameExtension: "mp4")!, UTType(filenameExtension: "mov")!,
            UTType(filenameExtension: "mkv")!, UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "wav")!, UTType(filenameExtension: "m4a")!,
            UTType(filenameExtension: "ogg")!]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !files.contains(url) { files.append(url) }
    }

    func removeSelected(_ indexSet: IndexSet) {
        for i in indexSet.sorted().reversed() where files.indices.contains(i) { files.remove(at: i) }
    }

    func addMusicFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, UTType(filenameExtension: "mp3")!,
            UTType(filenameExtension: "wav")!, UTType(filenameExtension: "m4a")!]
        guard panel.runModal() == .OK else { return }
        musicURL = panel.urls.first
    }

    func addOverlayVideo() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, UTType(filenameExtension: "mp4")!]
        guard panel.runModal() == .OK else { return }
        overlayVideoURL = panel.urls.first
    }

    func cancel() {
        isCancelled = true
        isProcessing = false
        statusText = "Annullato"
        processingTask?.cancel()
        processingTask = nil
    }

    func refreshAPIModels() async {
        let service = grammarService
        let models = await service.listModels()
        availableTextModels = models
        if !models.isEmpty {
            appendLog("✓ API: \(models.count) modelli trovati su \(apiBaseURL)")
        } else {
            appendLog("⚠ Nessun modello trovato su \(apiBaseURL)")
        }
    }

    func start() {
        guard !files.isEmpty else { return }
        isProcessing = true
        isCancelled = false
        progress = 0
        log = ""

        let filesCopy = files
        processingTask = Task { @MainActor in
            defer { isProcessing = false }
            for file in filesCopy {
                guard !isCancelled else { break }
                await processFile(file)
            }
            if !isCancelled { statusText = "Completato!"; progress = 1.0 }
        }
    }

    // MARK: - Core Pipeline

    private func processFile(_ file: URL) async {
        appendLog("\n==================================================")
        appendLog("File: \(file.lastPathComponent)")

        // Step 0: Extract audio
        let audioURL: URL
        if AudioService.isAudioFile(file) {
            audioURL = file
        } else {
            let cacheURL = file.deletingPathExtension().appendingPathExtension("_audio.wav")
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                appendLog("Cache audio trovata")
                audioURL = cacheURL
            } else {
                appendLog("Estrazione audio...")
                updateProgress(0, text: "Estrazione audio...")
                do { audioURL = try AudioService.extractAudio(from: file) }
                catch { appendLog("ERRORE: \(error.localizedDescription)"); return }
            }
        }

        let duration = AudioService.getDuration(audioURL)
        appendLog(String(format: "Durata: %.1fs", duration))

        // Step 1: Silence Removal (pre-process audio)
        var processedAudioURL = audioURL
        if enableSilenceRemoval {
            appendLog("Rimozione silenzi...")
            updateProgress(0.05, text: "Rimozione silenzi...")
            let silenceOut = file.deletingPathExtension().appendingPathExtension("_nosilence.wav")
            let settings = SilenceRemovalService.Settings(
                silenceThreshold: silenceThreshold, minSilenceDuration: minSilenceDuration)
            do {
                try await SilenceRemovalService.removeSilences(inputURL: audioURL, outputURL: silenceOut, settings: settings)
                processedAudioURL = silenceOut
                appendLog("✓ Silenzi rimossi")
            } catch {
                appendLog("⚠ Silence removal fallito: \(error.localizedDescription)")
            }
        }

        // Step 2: Noise Removal
        if enableNoiseRemoval {
            appendLog("Rimozione rumore...")
            updateProgress(0.1, text: "Rimozione rumore...")
            let noiseOut = processedAudioURL.deletingPathExtension().appendingPathExtension("_denoised.wav")
            let settings = NoiseRemovalService.Settings(strength: noiseStrength)
            do {
                try await NoiseRemovalService.removeNoise(inputURL: processedAudioURL, outputURL: noiseOut, settings: settings)
                processedAudioURL = noiseOut
                appendLog("✓ Rumore rimosso")
            } catch {
                appendLog("⚠ Noise removal fallito: \(error.localizedDescription)")
            }
        }

        // Step 3: Transcribe
        appendLog("Trascrizione con Whisper \(asrModel)...")
        updateProgress(0.2, text: "Trascrizione...")
        let segments: [Segment]
        do {
            segments = try await TranscriptionService.transcribe(audioURL: processedAudioURL, modelSize: asrModel, language: language)
        } catch {
            appendLog("ERRORE: \(error.localizedDescription)")
            return
        }

        // Cleanup temp audio files
        if processedAudioURL != audioURL { try? FileManager.default.removeItem(at: processedAudioURL) }
        if audioURL != file && audioURL != processedAudioURL { try? FileManager.default.removeItem(at: audioURL) }

        appendLog("Segmenti: \(segments.count)")

        // Step 4: Detect profile
        let activeProfile: VideoProfile
        if profileName == "auto" {
            activeProfile = ProfileDetector.detectProfile(from: segments)
            appendLog("Profilo: \(activeProfile.name.rawValue)")
        } else if let p = ProfileName(rawValue: profileName) {
            activeProfile = VideoProfile.named(p)
        } else { activeProfile = .conversational }

        // Step 5: Merge
        updateProgress(0.4, text: "Merge segmenti...")
        let merged = MergeService.mergeAndGroup(segments, profile: activeProfile)
        appendLog("Dopo merge: \(merged.count)")

        // Step 6: Grammar correction
        var corrected = merged
        if !textModel.isEmpty {
            updateProgress(0.5, text: "Correzione grammaticale...")
            corrected = await grammarService.correctSegments(merged, model: textModel, profile: activeProfile)
        }

        // Step 7: Normalize + punctuate
        updateProgress(0.7, text: "Normalizzazione...")
        corrected = correctFragments(corrected, profile: activeProfile)

        // Step 8: Export SRT
        let srtURL = file.deletingPathExtension().appendingPathExtension("srt")
        do {
            try SRTExporter.exportSRT(corrected, to: srtURL.path)
            appendLog("✓ SRT: \(srtURL.lastPathComponent)")
        } catch { appendLog("ERRORE export SRT: \(error.localizedDescription)") }

        // Step 9: Dual Language
        if enableDualLanguage {
            appendLog("Generazione sottotitoli bilingue...")
            updateProgress(0.8, text: "Traduzione...")
            let translated = await DualLanguageService.translate(segments: corrected, targetLanguage: secondaryLanguage, model: translationModel)

            let dualSRT = DualLanguageService.generateDualLanguageSRT(segments: corrected, secondarySegments: translated)
            let dualURL = file.deletingPathExtension().appendingPathExtension("dual.srt")
            do {
                try dualSRT.write(toFile: dualURL.path, atomically: true, encoding: .utf8)
                appendLog("✓ Dual SRT: \(dualURL.lastPathComponent)")
            } catch { appendLog("ERRORE dual SRT: \(error.localizedDescription)") }
        }

        // Step 10: Portrait Box
        if enablePortraitBox && !AudioService.isAudioFile(file) {
            appendLog("Conversione a 9:16...")
            updateProgress(0.85, text: "Portrait box...")
            let portraitURL = file.deletingPathExtension().appendingPathExtension("_portrait.mp4")
            let settings = PortraitBoxService.Settings(
                outputWidth: portraitWidth, outputHeight: portraitHeight,
                cropMode: PortraitBoxService.Settings.CropMode(rawValue: portraitCropMode) ?? .center,
                blurBackground: portraitBlurBackground)
            do {
                try await PortraitBoxService.convertToPortrait(inputURL: file, outputURL: portraitURL, settings: settings)
                appendLog("✓ Portrait: \(portraitURL.lastPathComponent)")
            } catch { appendLog("⚠ Portrait fallito: \(error.localizedDescription)") }
        }

        // Step 11: Music + Ducking
        if enableMusicDucking, let music = musicURL {
            appendLog("Aggiunta musica con ducking...")
            updateProgress(0.9, text: "Musica + ducking...")
            let duckURL = file.deletingPathExtension().appendingPathExtension("_music.mp4")
            let settings = MusicDuckingService.Settings(musicVolume: musicVolume, duckLevel: duckLevel)
            do {
                try await MusicDuckingService.addMusicWithDucking(speechURL: file, musicURL: music, outputURL: duckURL, settings: settings)
                appendLog("✓ Musica: \(duckURL.lastPathComponent)")
            } catch { appendLog("⚠ Musica fallita: \(error.localizedDescription)") }
        }

        // Step 12: Overlay
        if enableOverlay, let overlay = overlayVideoURL, !AudioService.isAudioFile(file) {
            appendLog("Applicazione overlay...")
            let overlayURL = file.deletingPathExtension().appendingPathExtension("_overlay.mp4")
            let settings = OverlayService.Settings(
                position: OverlayService.Settings.OverlayPosition(rawValue: overlayPosition) ?? .bottomRight,
                overlayScale: overlayScale)
            do {
                try await OverlayService.applyOverlay(mainVideoURL: file, overlayVideoURL: overlay, outputURL: overlayURL, settings: settings)
                appendLog("✓ Overlay: \(overlayURL.lastPathComponent)")
            } catch { appendLog("⚠ Overlay fallito: \(error.localizedDescription)") }
        }

        appendLog("✓ Elaborazione completata")
    }

    // MARK: - Helpers

    private func correctFragments(_ segments: [Segment], profile: VideoProfile) -> [Segment] {
        var result: [Segment] = []
        var ctx = BoundaryContext()
        for (i, seg) in segments.enumerated() {
            var s = seg
            let nextSeg = i + 1 < segments.count ? segments[i + 1] : nil
            let nextText = nextSeg?.text ?? ""
            let gap = nextSeg.map { $0.start - s.end } ?? 2.0
            s.text = TextNormalizer.normalizeText(s.text)
            s.text = TextNormalizer.fixPunctLocal(text: s.text, nextText: nextText, gapSec: gap, profile: profile, context: ctx)
            if let first = s.text.first, first.isLowercase { s.text = String(first).uppercased() + s.text.dropFirst() }
            ctx.prevGap = gap
            result.append(s)
        }
        return result
    }

    private func appendLog(_ msg: String) { log += msg + "\n" }
    private func updateProgress(_ pct: Double, text: String) { progress = pct; statusText = text }
}