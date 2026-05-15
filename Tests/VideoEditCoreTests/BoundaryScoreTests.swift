import Testing
import Foundation
@testable import VideoEditCore

@Test func testBoundaryScore() {
    let profile = VideoProfile.conversational

    let score = BoundaryScore.evaluate(
        currText: "Fine.", currEnd: 5.0,
        nextText: "Ora parliamo d'altro.", nextStart: 7.0,
        profile: profile
    )
    #expect(score > profile.boundaryThreshold, "Should break (new sentence after gap + punct)")

    let score2 = BoundaryScore.evaluate(
        currText: "Ciao", currEnd: 5.0,
        nextText: "mondo", nextStart: 5.3,
        profile: profile
    )
    #expect(score2 < profile.boundaryThreshold, "Should NOT break (short, no punct, small gap)")
}

@Test func testBoundaryScoreWithContext() {
    let profile = VideoProfile.conversational

    let score = BoundaryScore.evaluate(
        currText: "Ciao mondo.", currEnd: 5.0,
        nextText: "E adesso?", nextStart: 6.0,
        profile: profile
    )
    #expect(score > profile.boundaryThreshold, "Strong punct should break even before weak conj")

    let ctx = BoundaryContext(prevGap: 0.8, silenceAfter: 0)
    let score2 = BoundaryScore.evaluate(
        currText: "c'è anche", currEnd: 10.0,
        nextText: "il problema", nextStart: 10.6,
        profile: profile, context: ctx
    )
    #expect(score2 < profile.boundaryThreshold, "Short lowercase continuation should NOT break")
}

@Test func testBoundaryScore_casing() {
    let profile = VideoProfile.lecturing
    let score = BoundaryScore.evaluate(
        currText: "Poi c'è una cosa.", currEnd: 30.0,
        nextText: "Importantissima,", nextStart: 31.5,
        profile: profile
    )
    #expect(score > profile.boundaryThreshold, "Punct + uppercase should break")
}

@Test func testBoundaryScore_weakConj() {
    let profile = VideoProfile.conversational
    let score = BoundaryScore.evaluate(
        currText: "c'è anche", currEnd: 5.0,
        nextText: "e poi c'è", nextStart: 5.8,
        profile: profile
    )
    #expect(score < profile.boundaryThreshold, "Weak conj with no strong end should not break")

    let score2 = BoundaryScore.evaluate(
        currText: "Punto.", currEnd: 5.0,
        nextText: "E poi altro.", nextStart: 6.5,
        profile: profile
    )
    #expect(score2 > profile.boundaryThreshold, "Strong end should break even before E")
}

@Test func testShouldBreak() {
    let profile = VideoProfile.conversational
    let dec = BoundaryScore.shouldBreak(
        currText: "Fine.", currEnd: 5.0,
        nextText: "Nuova frase.", nextStart: 7.0,
        profile: profile
    )
    #expect(dec)

    let dec2 = BoundaryScore.shouldBreak(
        currText: "Ciao", currEnd: 5.0,
        nextText: "mondo", nextStart: 5.3,
        profile: profile
    )
    #expect(!dec2)
}
