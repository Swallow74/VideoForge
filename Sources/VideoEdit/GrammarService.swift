import Foundation
import VideoEditCore

/// Grammar correction via any OpenAI-compatible API (omlx, ollama, LM Studio, etc.)
public actor GrammarService {
    private let baseURL: URL
    private let apiKey: String
    private let session: URLSession
    private let cache = CorrectionCache()

    private static let systemPrompt = """
    Sei un correttore ortografico automatico per sottotitoli video italiani. \
    INPUT: una frase breve, possibilmente con errori di battitura, \
    accordo grammaticale o trascrizione automatica. \
    OUTPUT: restituisci SOLO la frase corretta, senza spiegazioni, senza virgolette, \
    senza prefissi come Correzione:, senza aggiungere frasi nuove, \
    senza completare pensieri lasciati volutamente incompleti. \
    NON aggiungere parole a meno che non siano strettamente necessarie per la grammatica. \
    NON togliere parole. NON cambiare il significato. NON punteggiare alla fine. \
    Se la frase è già corretta, restituiscila identica.
    """

    public init(baseURL: String = "http://127.0.0.1:8000/v1", apiKey: String? = nil) {
        var urlStr = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
        if !urlStr.hasSuffix("/v1") { urlStr += "/v1" }
        self.baseURL = URL(string: urlStr)!
        self.apiKey = apiKey ?? EnvLoader.load()["API_KEY"] ?? ProcessInfo.processInfo.environment["OMLX_API_KEY"] ?? ""
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    /// List available models from the API.
    public func listModels() async -> [String] {
        let url = baseURL.appendingPathComponent("models")
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let modelList = json["data"] as? [[String: Any]] else { return [] }

        return modelList.compactMap { $0["id"] as? String }.sorted()
    }

    /// Test connectivity to the API endpoint.
    public func checkConnection() async -> Bool {
        let models = await listModels()
        return !models.isEmpty
    }

    /// Correct all segments using the API.
    public func correctSegments(
        _ segments: [Segment],
        model: String,
        profile: VideoProfile
    ) async -> [Segment] {
        var result: [Segment] = []
        let batchSize = 5

        for i in stride(from: 0, to: segments.count, by: batchSize) {
            let batch = Array(segments[i..<min(i + batchSize, segments.count)])
            let corrected = await correctBatch(batch, model: model)
            result.append(contentsOf: corrected)
        }

        var ctx = BoundaryContext()
        for i in result.indices {
            let nextSeg = i + 1 < result.count ? result[i + 1] : nil
            let nextText = nextSeg?.text ?? ""
            let gap = nextSeg.map { $0.start - result[i].end } ?? 2.0

            result[i].text = TextNormalizer.fixPunctLocal(
                text: result[i].text, nextText: nextText,
                gapSec: gap, profile: profile, context: ctx
            )

            if let first = result[i].text.first, first.isLowercase {
                result[i].text = String(first).uppercased() + result[i].text.dropFirst()
            }

            ctx.prevGap = gap
        }

        return result
    }

    // MARK: - Private

    private func correctBatch(_ segments: [Segment], model: String) async -> [Segment] {
        var result = segments

        for i in result.indices {
            let text = result[i].text
            guard TextNormalizer.needsQwen(text) else {
                result[i].text = TextNormalizer.normalizeText(text)
                continue
            }

            if let cached = cache.get(text) {
                result[i].text = cached
                continue
            }

            guard let corrected = await correctText(text, model: model) else { continue }

            let validated = validateOutput(corrected, original: text)
            if !validated.isEmpty {
                cache.set(original: text, corrected: validated)
                result[i].text = validated
            }
        }

        return result
    }

    private func correctText(_ text: String, model: String) async -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": text],
            ],
            "temperature": 0.0,
            "max_tokens": text.count * 3 + 30,
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData

        guard let (data, _) = try? await session.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return nil
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func validateOutput(_ output: String, original: String) -> String {
        var stripped = output.trimmingCharacters(in: .whitespacesAndNewlines)
        stripped = stripped.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))

        let wordsOut = stripped.split(separator: " ").count
        let wordsIn = original.split(separator: " ").count

        guard wordsOut <= wordsIn * 2 else { return "" }

        if stripped.contains("\n") || stripped.contains("→") ||
           stripped.contains("Correzione") || stripped.contains("Nota") ||
           stripped.contains("**") {
            return String(stripped.split(separator: "\n").first ?? "")
        }

        if stripped.contains(":") && stripped.split(separator: " ").count < 6 {
            return String(stripped.split(separator: ":").last ?? "").trimmingCharacters(in: .whitespaces)
        }

        return stripped
    }
}