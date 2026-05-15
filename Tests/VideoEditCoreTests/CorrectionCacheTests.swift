import Testing
import Foundation
@testable import VideoEditCore

@Test func testCacheStoreAndRetrieve() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    let cache = CorrectionCache(cacheDir: tmp)

    cache.set(original: "ciao mondo", corrected: "Ciao mondo")
    let result = cache.get("ciao mondo")
    #expect(result == "Ciao mondo")
}

@Test func testCacheReturnsNilForMissing() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    let cache = CorrectionCache(cacheDir: tmp)

    let result = cache.get("inesistente")
    #expect(result == nil)
}

@Test func testCacheSkipsIdentical() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    let cache = CorrectionCache(cacheDir: tmp)

    cache.set(original: "ok", corrected: "ok")
    let result = cache.get("ok")
    #expect(result == nil, "Should not store when text unchanged")
}

@Test func testCacheGetOrCorrect() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    let cache = CorrectionCache(cacheDir: tmp)

    var callCount = 0
    func corrector(_ t: String) -> String {
        callCount += 1
        return "\(t) corretto"
    }

    let r1 = cache.getOrCorrect("test", correctFn: corrector)
    #expect(r1 == "test corretto")
    #expect(callCount == 1)

    let r2 = cache.getOrCorrect("test", correctFn: corrector)
    #expect(r2 == "test corretto")
    #expect(callCount == 1, "Should not call corrector again")
}

@Test func testCachePersistence() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    do {
        let cache = CorrectionCache(cacheDir: tmp)
        cache.set(original: "persist test", corrected: "persist corretto")
    }

    let cache2 = CorrectionCache(cacheDir: tmp)
    let result = cache2.get("persist test")
    #expect(result == "persist corretto")
}

@Test func testCacheComplexText() {
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-cache-\(UUID().uuidString)")
    let cache = CorrectionCache(cacheDir: tmp)

    let longText = "Questa è una frase molto lunga per testare il corretto funzionamento della cache anche con testi complessi con numeri 12345 e simboli @#$%"
    let expected = "Versione corretta di un testo lungo"
    cache.set(original: longText, corrected: expected)

    let result = cache.get(longText)
    #expect(result == expected)
}
