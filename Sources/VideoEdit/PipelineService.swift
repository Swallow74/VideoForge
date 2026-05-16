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

    // MARK: - Steps configuration

    private struct StepWeights {
        var extraction: Double = 5
        var silence: Double = 0
        var noise: Double = 0
        var transcription: Double = 40
        var profile: Double = 2
        var merge: Double = 3
        var grammar: Double = 0
        var normalize: Double = 5
        var export: Double = 2
        var dualLanguage: Double = 0
        var portrait: Double = 0
        var music: Double = 0
        var overlay: Double = 0
        var cleanup: Double = 3

        var total: Double {
            extraction + silence + noise + transcription + profile + merge
            + grammar + normalize + export + dualLanguage + portrait + music + overlay + cleanup
        }
    }

    private func computeWeights() -> StepWeights {
        StepWeights(
            silence: enableSilenceRemoval ? 5 : 0,
            noise: enableNoiseRemoval ? 5 : 0,
            grammar: !textModel.isEmpty ? 10 : 0,
            dualLanguage: enableDualLanguage ? 8 : 0,
            portrait: enablePortraitBox ? 8 : 0,
            music: enableMusicDucking ? 5 : 0,
            overlay: enableOverlay ? 5 : 0
        )
    }

    private var stepNumber = 0
    private var totalSteps = 0

    private func beginSteps(_ w: StepWeights) {
        stepNumber = 0
        totalSteps = 0
        if w.extraction > 0 { totalSteps += 1 }
        if w.silence > 0 { totalSteps += 1 }
        if w.noise > 0 { totalSteps += 1 }
        totalSteps += 1 // transcription
        if w.profile > 0 { totalSteps += 1 }
        if w.merge > 0 { totalSteps += 1 }
        if w.grammar > 0 { totalSteps += 1 }
        if w.normalize > 0 { totalSteps += 1 }
        if w.export > 0 { totalSteps += 1 }
        if w.dualLanguage > 0 { totalSteps += 1 }
        if w.portrait > 0 { totalSteps += 1 }
        if w.music > 0 { totalSteps += 1 }
        if w.overlay > 0 { totalSteps += 1 }
    }

    private func advanceStep(_ w: StepWeights, _ current: inout Double, label: String) {
        stepNumber += 1
        current += w.total > 0 ? (100.0 / w.total) : 0
        let pct = min(current / 100.0, 0.99)
        progress = pct
        statusText = "[\(stepNumber)/\(totalSteps)] \(label)"
    }

    // MARK: - Core Pipeline

    private func processFile(_ file: URL) async {
        let w = computeWeights()
        beginSteps(w)
        var pct: Double = 0
        let fmt = DateFormatter()
        fmt.dateFormat = "HH:mm:ss"

        func ts() -> String { fmt.string(from: Date()) }
        func log(_ msg: String) { appendLog("[\(ts())] \(msg)") }
        func step(_ label: String) { advanceStep(w, &pct, label: label) }

        log("═══════════════════════════════════════════")
        log("File: \(file.lastPathComponent)")
        log("Modelli: Whisper=\(asrModel)  Correzione=\(textModel.isEmpty ? "nessuna" : textModel)")
        log("Opzioni: \(describeOptions())")

        // Step 0: Extract audio
        let audioURL: URL
        if AudioService.isAudioFile(file) {
            step("Analisi file audio")
            audioURL = file
            log("File audio riconosciuto")
        } else {
            step("Estrazione audio")
            let cacheURL = file.deletingPathExtension().appendingPathExtension("_audio.wav")
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                log("Cache audio trovata → uso \(cacheURL.lastPathComponent)")
                audioURL = cacheURL
            } else {
                log("Estrazione traccia audio con ffmpeg...")
                do {
                    audioURL = try AudioService.extractAudio(from: file)
                    log("✓ Audio estratto: \(audioURL.lastPathComponent)")
                } catch {
                    log("✗ ERRORE estrazione audio: \(error.localizedDescription)")
                    log("  → Verifica che ffmpeg sia installato")
                    return
                }
            }
        }

        let duration = AudioService.getDuration(audioURL)
        log("Durata: \(String(format: "%.1f", duration))s (\(String(format: "%.1f", duration/60)) min)")

        // Silence Removal
        var processedAudioURL = audioURL
        if enableSilenceRemoval {
            step("Rimozione silenzi")
            log("Soglia: \(Int(silenceThreshold)) dB, durata min: \(minSilenceDuration)s")
            let silenceOut = file.deletingPathExtension().appendingPathExtension("_nosilence.wav")
            let settings = SilenceRemovalService.Settings(
                silenceThreshold: silenceThreshold, minSilenceDuration: minSilenceDuration)
            do {
                try await SilenceRemovalService.removeSilences(inputURL: audioURL, outputURL: silenceOut, settings: settings)
                processedAudioURL = silenceOut
                log("✓ Silenzi rimossi → \(silenceOut.lastPathComponent)")
            } catch {
                log("⚠ Silence removal fallito: \(error.localizedDescription)")
            }
        }

        // Noise Removal
        if enableNoiseRemoval {
            step("Rimozione rumore")
            log("Forza riduzione: \(noiseStrength)")
            let noiseOut = processedAudioURL.deletingPathExtension().appendingPathExtension("_denoised.wav")
            let settings = NoiseRemovalService.Settings(strength: noiseStrength)
            do {
                try await NoiseRemovalService.removeNoise(inputURL: processedAudioURL, outputURL: noiseOut, settings: settings)
                processedAudioURL = noiseOut
                log("✓ Rumore rimosso → \(noiseOut.lastPathComponent)")
            } catch {
                log("⚠ Noise removal fallito: \(error.localizedDescription)")
            }
        }

        // Venv setup
        if !FileManager.default.isExecutableFile(atPath: DependencyService.venvPython) {
            step("Setup ambiente Python")
            log("Creazione ambiente virtuale con mlx-whisper...")
            do {
                try await DependencyService.setupVenv()
                log("✓ Ambiente Python pronto: ~/.videoforge/venv")
            } catch {
                log("✗ ERRORE setup Python: \(error.localizedDescription)")
                return
            }
        } else {
            let ok = (try? await DependencyService.ensureVenvReady()) != nil
            if !ok {
                log("✗ ERRORE: mlx-whisper non disponibile nel venv")
                return
            }
        }

        // Transcribe
        step("Trascrizione (\(asrModel))")
        log("Caricamento modello Whisper \(asrModel)...")
        let segments: [Segment]
        do {
            segments = try await TranscriptionService.transcribe(audioURL: processedAudioURL, modelSize: asrModel, language: language)
        } catch {
            log("✗ ERRORE trascrizione: \(error.localizedDescription)")
            return
        }

        // Cleanup temp audio
        if processedAudioURL != audioURL { try? FileManager.default.removeItem(at: processedAudioURL) }
        if audioURL != file && audioURL != processedAudioURL { try? FileManager.default.removeItem(at: audioURL) }

        log("✓ \(segments.count) segmenti grezzi")

        // Detect profile
        step("Rilevamento profilo")
        let activeProfile: VideoProfile
        if profileName == "auto" {
            activeProfile = ProfileDetector.detectProfile(from: segments)
            log("Profilo rilevato: \(activeProfile.name.rawValue)")
        } else if let p = ProfileName(rawValue: profileName) {
            activeProfile = VideoProfile.named(p)
            log("Profilo manuale: \(p.rawValue)")
        } else { activeProfile = .conversational }

        // Merge
        step("Merge segmenti")
        let merged = MergeService.mergeAndGroup(segments, profile: activeProfile)
        log("Fusione intelligente: \(segments.count) → \(merged.count) segmenti")

        // Grammar correction
        var corrected = merged
        if !textModel.isEmpty {
            step("Correzione grammaticale")
            log("Modello: \(textModel)")
            corrected = await grammarService.correctSegments(merged, model: textModel, profile: activeProfile)
            log("✓ Correzione completata su \(corrected.count) segmenti")
        }

        // Normalize + punctuate
        step("Normalizzazione e punteggiatura")
        corrected = correctFragments(corrected, profile: activeProfile)
        log("✓ Punteggiatura adattiva applicata")

        // Export SRT
        step("Export SRT")
        let srtURL = file.deletingPathExtension().appendingPathExtension("srt")
        do {
            try SRTExporter.exportSRT(corrected, to: srtURL.path)
            log("✓ SRT salvato: \(srtURL.lastPathComponent)")
        } catch {
            log("✗ ERRORE export SRT: \(error.localizedDescription)")
        }

        // Dual Language
        if enableDualLanguage {
            step("Sottotitoli bilingue")
            log("Seconda lingua: \(secondaryLanguage.uppercased())")
            let translated = await DualLanguageService.translate(segments: corrected, targetLanguage: secondaryLanguage, model: translationModel)
            let dualSRT = DualLanguageService.generateDualLanguageSRT(segments: corrected, secondarySegments: translated)
            let dualURL = file.deletingPathExtension().appendingPathExtension("dual.srt")
            do {
                try dualSRT.write(toFile: dualURL.path, atomically: true, encoding: .utf8)
                log("✓ Dual SRT: \(dualURL.lastPathComponent)")
            } catch {
                log("✗ ERRORE dual SRT: \(error.localizedDescription)")
            }
        }

        // Portrait Box
        if enablePortraitBox && !AudioService.isAudioFile(file) {
            step("Conversione 9:16 (Portrait)")
            log("Ritaglio: \(portraitCropMode), sfondo sfocato: \(portraitBlurBackground)")
            let portraitURL = file.deletingPathExtension().appendingPathExtension("_portrait.mp4")
            let settings = PortraitBoxService.Settings(
                outputWidth: portraitWidth, outputHeight: portraitHeight,
                cropMode: PortraitBoxService.Settings.CropMode(rawValue: portraitCropMode) ?? .center,
                blurBackground: portraitBlurBackground)
            do {
                try await PortraitBoxService.convertToPortrait(inputURL: file, outputURL: portraitURL, settings: settings)
                log("✓ Portrait: \(portraitURL.lastPathComponent)")
            } catch {
                log("⚠ Portrait fallito: \(error.localizedDescription)")
            }
        }

        // Music + Ducking
        if enableMusicDucking, let music = musicURL {
            step("Musica + Auto-Ducking")
            log("File musica: \(music.lastPathComponent), volume: \(musicVolume), duck: \(duckLevel)")
            let duckURL = file.deletingPathExtension().appendingPathExtension("_music.mp4")
            let settings = MusicDuckingService.Settings(musicVolume: musicVolume, duckLevel: duckLevel)
            do {
                try await MusicDuckingService.addMusicWithDucking(speechURL: file, musicURL: music, outputURL: duckURL, settings: settings)
                log("✓ Musica: \(duckURL.lastPathComponent)")
            } catch {
                log("⚠ Musica fallita: \(error.localizedDescription)")
            }
        }

        // Overlay
        if enableOverlay, let overlay = overlayVideoURL, !AudioService.isAudioFile(file) {
            step("Overlay PIP")
            log("Video overlay: \(overlay.lastPathComponent), posizione: \(overlayPosition), scala: \(overlayScale)")
            let overlayURL = file.deletingPathExtension().appendingPathExtension("_overlay.mp4")
            let settings = OverlayService.Settings(
                position: OverlayService.Settings.OverlayPosition(rawValue: overlayPosition) ?? .bottomRight,
                overlayScale: overlayScale)
            do {
                try await OverlayService.applyOverlay(mainVideoURL: file, overlayVideoURL: overlay, outputURL: overlayURL, settings: settings)
                log("✓ Overlay: \(overlayURL.lastPathComponent)")
            } catch {
                log("⚠ Overlay fallito: \(error.localizedDescription)")
            }
        }

        log("━  Elaborazione completata  ━")
        pct = 100
        progress = 1.0
        statusText = "✓ Completato: \(file.lastPathComponent)"
    }

    // MARK: - Helpers

    private func describeOptions() -> String {
        var opts: [String] = []
        if enableSilenceRemoval { opts.append("silence") }
        if enableNoiseRemoval { opts.append("noise") }
        if enablePortraitBox { opts.append("portrait") }
        if enableOverlay { opts.append("overlay") }
        if enableMusicDucking { opts.append("music") }
        if enableDualLanguage { opts.append("bilingue") }
        if !textModel.isEmpty { opts.append("grammar") }
        return opts.isEmpty ? "nessuna" : opts.joined(separator: ", ")
    }

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
}
