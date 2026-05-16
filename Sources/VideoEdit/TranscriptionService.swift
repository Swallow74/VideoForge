import Foundation
import VideoEditCore

public enum TranscriptionError: LocalizedError {
    case pythonNotFound
    case scriptNotFound
    case transcriptionFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 non trovato. Installa Python 3.12+ con Homebrew."
        case .scriptNotFound:
            return "Script transcribe_audio.py non trovato nel bundle."
        case .transcriptionFailed(let msg):
            return msg
        case .cancelled:
            return "Trascrizione annullata."
        }
    }
}

public enum TranscriptionService {
    public static func transcribe(
        audioURL: URL,
        modelSize: String = "large-v3",
        language: String? = nil,
        onProgress: (@Sendable (Double, Double, Double) -> Void)? = nil
    ) async throws -> [Segment] {
        let script = try findScript()
        let python = try await resolvePython()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: python)
        var args = [script, audioURL.path, "--model", modelSize]
        if let lang = language { args += ["--language", lang] }
        process.arguments = args

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // macOS Finder usa PATH minimale. mlx-whisper chiama ffmpeg internamente.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = (env["PATH"] ?? "") + ":\(NSHomeDirectory())/.videoforge/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = env

        do {
            try process.run()
        } catch {
            throw TranscriptionError.transcriptionFailed(
                "Impossibile avviare Python3. Installa Python 3.12+ con Homebrew:\n  brew install python@3.12"
            )
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: errorData, encoding: .utf8) ?? "errore sconosciuto"
            let trimmed = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("No module named 'mlx_whisper'") {
                throw TranscriptionError.transcriptionFailed(
                    "Dipendenze Python mancanti. Avvia il setup dall'app o esegui:\n  \(DependencyService.venvPython) -m pip install mlx-whisper"
                )
            }
            throw TranscriptionError.transcriptionFailed(trimmed)
        }

        let segments = try parseSegments(from: outputData)
        onProgress?(1.0, Double(segments.count), Double(segments.count))
        return segments
    }

    // MARK: - Helpers

    private static func resolvePython() async throws -> String {
        // Prefer the dedicated venv (has all deps)
        if FileManager.default.isExecutableFile(atPath: DependencyService.venvPython) {
            return DependencyService.venvPython
        }
        // Fallback: system Python (mlx-whisper might be installed globally)
        for path in systemPythonPaths where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        throw TranscriptionError.pythonNotFound
    }

    private static let systemPythonPaths = [
        "/opt/homebrew/bin/python3.14",
        "/opt/homebrew/bin/python3.13",
        "/opt/homebrew/bin/python3.12",
        "/opt/homebrew/bin/python3.11",
        "/opt/homebrew/bin/python3.10",
        "/opt/homebrew/bin/python3",
        "/usr/local/bin/python3",
        "/usr/bin/python3",
    ]

    private static func findScript() throws -> String {
        if let bundlePath = Bundle.main.path(forResource: "transcribe_audio", ofType: "py") {
            return bundlePath
        }
        let cwd = FileManager.default.currentDirectoryPath
        let devPath = "\(cwd)/Sources/VideoEdit/Resources/transcribe_audio.py"
        if FileManager.default.fileExists(atPath: devPath) {
            return devPath
        }
        throw TranscriptionError.scriptNotFound
    }

    private static func parseSegments(from data: Data) throws -> [Segment] {
        let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        guard let segmentsJSON = json else {
            throw TranscriptionError.transcriptionFailed("output JSON non valido")
        }

        return segmentsJSON.map { segDict in
            let start = segDict["start"] as? Double ?? 0
            let end = segDict["end"] as? Double ?? 0
            let text = segDict["text"] as? String ?? ""

            let words: [WordTimestamp] = (segDict["words"] as? [[String: Any]])?.map { w in
                WordTimestamp(
                    word: w["word"] as? String ?? "",
                    start: w["start"] as? Double ?? 0,
                    end: w["end"] as? Double ?? 0
                )
            } ?? []

            return Segment(start: start, end: end, text: text, words: words)
        }
    }
}
