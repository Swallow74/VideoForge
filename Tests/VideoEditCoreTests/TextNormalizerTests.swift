import Testing
import Foundation
@testable import VideoEditCore

@Test func testNormalizeWhitespace() {
    let result = TextNormalizer.normalizeText("  ciao   mondo  ")
    #expect(result == "Ciao mondo")
}

@Test func testNormalizeCapitalize() {
    let result = TextNormalizer.normalizeText("ciao mondo")
    #expect(result == "Ciao mondo")
}

@Test func testNormalizePunctSpacing() {
    let result = TextNormalizer.normalizeText("Ciao , mondo")
    #expect(result == "Ciao, mondo")
}

@Test func testNormalizeSentenceBreak() {
    let result = TextNormalizer.normalizeText("Fine.Inizia")
    #expect(result == "Fine. Inizia")
}

@Test func testFixPunctBreak() {
    // Long sentence with strong gap → should break and add period
    let result = TextNormalizer.fixPunctLocal(
        text: "Questa è una frase lunga che finisce",
        nextText: "Nuova frase dopo pausa",
        gapSec: 3.0,
        profile: .conversational
    )
    #expect(result.hasSuffix("."), "Should add period when breaking")
    #expect(result.hasPrefix("Q"), "Should capitalize first letter")
}

@Test func testFixPunctNoBreak() {
    let result = TextNormalizer.fixPunctLocal(
        text: "Ciao",
        nextText: "mondo",
        gapSec: 0.3,
        profile: .conversational
    )
    #expect(result == "Ciao", "Should NOT add period when continuing")
    #expect(!result.hasSuffix("."), "No trailing period")
}

@Test func testFixPunctSingleWord() {
    let result = TextNormalizer.fixPunctLocal(
        text: "Bene.",
        nextText: "",
        gapSec: 1.0,
        profile: .conversational
    )
    #expect(result == "Bene.", "Single word with punct should keep it when no next")
}

@Test func testNeedsQwenShort() {
    #expect(!TextNormalizer.needsQwen("Frase breve"))
}

@Test func testNeedsQwenWithBrackets() {
    #expect(TextNormalizer.needsQwen("Frase molto lunga che contiene [parentesi] e va corretta"))
}

@Test func testNeedsQwenLoop() {
    #expect(!TextNormalizer.needsQwen("la la la"))
}

@Test func testNeedsQwenFalseForNormal() {
    #expect(!TextNormalizer.needsQwen("Questa è una frase lunga ma normale senza problemi"))
}
