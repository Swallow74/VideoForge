import Foundation
import CryptoKit

public final class CorrectionCache: @unchecked Sendable {
    private let cacheDir: URL
    private var memCache: [String: String] = [:]
    private let queue = DispatchQueue(label: "correction-cache", attributes: .concurrent)

    public init(cacheDir: URL? = nil) {
        if let dir = cacheDir {
            self.cacheDir = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.cacheDir = home.appendingPathComponent(".cache/correzioni")
        }
        try? FileManager.default.createDirectory(at: self.cacheDir, withIntermediateDirectories: true)
    }

    private func hash(_ text: String) -> String {
        guard let data = text.data(using: .utf8) else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.prefix(32).joined()
    }

    public func get(_ text: String) -> String? {
        var result: String?
        queue.sync {
            if let cached = memCache[text] {
                result = cached
                return
            }
            let h = hash(text)
            let path = cacheDir.appendingPathComponent("\(h).txt")
            if let val = try? String(contentsOf: path, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) as String {
                memCache[text] = val
                result = val
            }
        }
        return result
    }

    public func set(original: String, corrected: String) {
        guard original != corrected else { return }
        queue.sync(flags: .barrier) {
            self.memCache[original] = corrected
            let h = self.hash(original)
            let path = self.cacheDir.appendingPathComponent("\(h).txt")
            try? corrected.trimmingCharacters(in: .whitespacesAndNewlines).write(to: path, atomically: true, encoding: .utf8)
        }
    }

    public func getOrCorrect(_ text: String, correctFn: (String) -> String) -> String {
        if let cached = get(text) {
            return cached
        }
        let corrected = correctFn(text)
        set(original: text, corrected: corrected)
        return corrected
    }

    public func clear() {
        queue.async(flags: .barrier) {
            self.memCache.removeAll()
        }
    }
}