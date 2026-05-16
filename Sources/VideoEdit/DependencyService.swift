import Foundation

public enum DependencyError: Error {
    case installFailed(String)
}

public struct DependencyStatus: Sendable {
    public let name: String
    public let installed: Bool
    public let optional: Bool
    public let version: String?
    public let installHint: String
}

public enum DependencyService {
    public static let venvPath = "\(NSHomeDirectory())/.videoforge/venv"
    public static var venvPython: String { "\(venvPath)/bin/python3" }

    public static func checkAll() -> [DependencyStatus] {
        [
            checkHomebrew(),
            checkFFmpeg(),
            checkPython(),
            checkVenv(),
            checkOmlx(),
        ]
    }

    public static func checkHomebrew() -> DependencyStatus {
        let installed = checkExecutable("brew")
        return DependencyStatus(
            name: "Homebrew",
            installed: installed,
            optional: false,
            version: installed ? shell("brew --version").first : nil,
            installHint: "https://brew.sh"
        )
    }

    public static func checkFFmpeg() -> DependencyStatus {
        let installed = checkExecutable("ffmpeg")
        return DependencyStatus(
            name: "ffmpeg",
            installed: installed,
            optional: false,
            version: installed ? shell("ffmpeg -version").first?.components(separatedBy: " ").dropFirst(2).first : nil,
            installHint: "brew install ffmpeg"
        )
    }

    public static func checkPython() -> DependencyStatus {
        let installed = checkExecutable("python3")
        let version = installed ? shell("python3 --version").first : nil
        return DependencyStatus(
            name: "Python 3",
            installed: installed,
            optional: false,
            version: version,
            installHint: "brew install python@3.12"
        )
    }

    public static func checkVenv() -> DependencyStatus {
        guard FileManager.default.isExecutableFile(atPath: venvPython) else {
            return DependencyStatus(
                name: "mlx-whisper (venv)",
                installed: false,
                optional: false,
                version: nil,
                installHint: "Clicca 'Installa' per creare l'ambiente virtuale"
            )
        }
        let result = shell("\(venvPython) -c \"import mlx_whisper; print(mlx_whisper.__version__)\"")
        let installed = !result.isEmpty
        return DependencyStatus(
            name: "mlx-whisper (venv)",
            installed: installed,
            optional: false,
            version: installed ? result.first : nil,
            installHint: "Esegui manualmente: \(venvPython) -m pip install mlx-whisper"
        )
    }

    public static func checkOmlx() -> DependencyStatus {
        let installed = checkExecutable("omlx") || checkURL("http://127.0.0.1:8000/v1/models")
        var version: String? = nil
        if checkExecutable("omlx") {
            version = shell("omlx --version 2>/dev/null").first
        }
        return DependencyStatus(
            name: "omlx / LLM server",
            installed: installed,
            optional: true,
            version: version,
            installHint: "brew install omlx  oppure  usa Ollama/LM Studio"
        )
    }

    public static func installFFmpeg() async throws {
        try await downloadFFmpeg()
    }

    public static func installPython() async throws {
        try runScript("brew install python@3.12")
    }

    public static func installMLXWhisper() async throws {
        try await setupVenv()
    }

    /// Trova ffmpeg: prima system paths, poi copia locale, infine download.
    public static func findOrDownloadFFmpeg() async throws -> String {
        let localPath = "\(NSHomeDirectory())/.videoforge/bin/ffmpeg"
        for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"] {
            if FileManager.default.isExecutableFile(atPath: p) { return p }
        }
        if FileManager.default.isExecutableFile(atPath: localPath) { return localPath }
        try await downloadFFmpeg()
        return localPath
    }

    private static func downloadFFmpeg() async throws {
        let binDir = "\(NSHomeDirectory())/.videoforge/bin"
        try FileManager.default.createDirectory(atPath: binDir, withIntermediateDirectories: true)

        try await downloadAndExtract(
            url: "https://evermeet.cx/ffmpeg/ffmpeg-7.1.zip",
            name: "ffmpeg",
            binDir: binDir
        )
        // ffprobe non viene scaricato (evermeet.cx non lo fornisce come statico separato).
        // getDuration() ritorna 0 come fallback se manca, non blocca nulla.
    }

    private static func downloadAndExtract(url: String, name: String, binDir: String) async throws {
        let zipPath = "\(binDir)/\(name).zip"
        let data = try await URLSession.shared.data(from: URL(string: url)!).0
        try data.write(to: URL(fileURLWithPath: zipPath))
        _ = try await shellAsync("cd '\(binDir)' && unzip -o '\(name).zip' 2>/dev/null && rm '\(name).zip'")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: "\(binDir)/\(name)")
        guard FileManager.default.isExecutableFile(atPath: "\(binDir)/\(name)") else {
            throw DependencyError.installFailed("Download \(name) fallito")
        }
    }

    public static func setupVenv() async throws {
        let basePath = "\(NSHomeDirectory())/.videoforge"
        try FileManager.default.createDirectory(atPath: basePath, withIntermediateDirectories: true)

        guard let pythonPath = findSystemPython() else {
            throw DependencyError.installFailed("Python 3 non trovato. Scarica da python.org o: brew install python@3.12")
        }

        // Step 0: Ensure ffmpeg is available (scarica statico se mancante)
        _ = try await findOrDownloadFFmpeg()

        // Step 1: Create venv
        var result = try await shellAsync("\(pythonPath) -m venv \(venvPath)")
        guard result == 0 else {
            throw DependencyError.installFailed("Creazione venv fallita")
        }

        // Step 2: Upgrade pip
        _ = try await shellAsync("\(venvPython) -m pip install --upgrade pip")

        // Step 3: Install mlx-whisper
        result = try await shellAsync("\(venvPython) -m pip install mlx-whisper")
        guard result == 0 else {
            throw DependencyError.installFailed("Installazione mlx-whisper fallita")
        }
    }

    public static func uninstallVenv() {
        try? FileManager.default.removeItem(atPath: "\(NSHomeDirectory())/.videoforge")
    }

    // MARK: - Private

    private static func findSystemPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    private static func checkExecutable(_ name: String) -> Bool {
        let result = shell("which \(name) 2>/dev/null")
        return !result.isEmpty
    }

    private static func checkURL(_ url: String) -> Bool {
        guard let u = URL(string: url) else { return false }
        let semaphore = DispatchSemaphore(value: 0)
        var available = false
        let task = URLSession.shared.dataTask(with: u) { _, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                available = true
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 3)
        return available
    }

    private static func shell(_ cmd: String) -> [String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return [] }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }
    }

    private static func shellAsync(_ cmd: String) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let box = ProcessBox()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", cmd]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    box.process = nil
                    continuation.resume(returning: proc.terminationStatus)
                }
            }
            do {
                try process.run()
                box.process = process
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func runScript(_ cmd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", cmd]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DependencyError.installFailed("Installation failed: \(cmd)")
        }
    }

    // MARK: - Setup helpers for TranscriptionService

    public static func ensureVenvReady() async throws -> String {
        if FileManager.default.isExecutableFile(atPath: venvPython) {
            let check = try await shellAsync("\(venvPython) -c \"import mlx_whisper\"")
            if check == 0 { return venvPython }
        }
        try await setupVenv()
        return venvPython
    }

    // MARK: - Process box to prevent premature deallocation

    private final class ProcessBox: @unchecked Sendable {
        var process: Process?
    }
}
