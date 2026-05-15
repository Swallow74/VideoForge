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
    public static func checkAll() -> [DependencyStatus] {
        [
            checkHomebrew(),
            checkFFmpeg(),
            checkPython(),
            checkMLXWhisper(),
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
            installHint: "https://brew.sh o: /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
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

    public static func checkMLXWhisper() -> DependencyStatus {
        guard checkExecutable("python3") else {
            return DependencyStatus(
                name: "mlx-whisper",
                installed: false,
                optional: false,
                version: nil,
                installHint: "Installa Python prima, poi: pip install mlx-whisper"
            )
        }
        let result = shell("python3 -c \"import mlx_whisper; print(mlx_whisper.__version__)\"")
        let installed = !result.isEmpty
        return DependencyStatus(
            name: "mlx-whisper",
            installed: installed,
            optional: false,
            version: installed ? result.first : nil,
            installHint: "pip install mlx-whisper"
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
        try runScript("brew install ffmpeg")
    }

    public static func installPython() async throws {
        try runScript("brew install python@3.12")
    }

    public static func installMLXWhisper() async throws {
        try runScript("python3 -m pip install mlx-whisper")
    }

    public static func installOmlx() async throws {
        try runScript("brew install omlx")
    }

    // MARK: - Private

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
}