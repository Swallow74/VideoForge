import Foundation

public enum EnvLoader {
    private static let envPath = "\(NSHomeDirectory())/.videoforge/.env"

    public static func load() -> [String: String] {
        guard let content = try? String(contentsOfFile: envPath, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                result[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }

    @discardableResult
    public static func save(_ key: String, value: String) -> Bool {
        let dir = "\(NSHomeDirectory())/.videoforge"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var current = load()
        current[key] = value
        let lines = current.map { "\($0.key)=\($0.value)" }.sorted()
        do {
            try lines.joined(separator: "\n").write(toFile: envPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }
}
