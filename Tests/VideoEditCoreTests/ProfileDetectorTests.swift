import Testing
import Foundation
@testable import VideoEditCore

@Test func testDetectConversational() {
    let segs = (0..<30).map { _ in
        Segment(start: 0, end: 2.0, text: "Ciao come stai? Tutto bene?")
    }
    let profile = ProfileDetector.detectProfile(from: segs)
    #expect(profile.name == .conversational)
}

@Test func testDetectLecturing() {
    let longText = Array(repeating: "Questa è una frase molto lunga che supera abbondantemente i sessanta caratteri ed è tipica di un discorso strutturato", count: 10).joined(separator: " ")
    let segs = (0..<30).map { _ in
        Segment(start: 0, end: 5.0, text: longText)
    }
    let profile = ProfileDetector.detectProfile(from: segs)
    #expect(profile.name == .lecturing)
}

@Test func testDetectEmpty() {
    let profile = ProfileDetector.detectProfile(from: [])
    #expect(profile.name == .conversational)
}

@Test func testProfileValues() {
    #expect(VideoProfile.conversational.boundaryThreshold == 0.55)
    #expect(VideoProfile.lecturing.boundaryThreshold == 0.70)
    #expect(VideoProfile.technical.boundaryThreshold == 0.62)

    #expect(VideoProfile.conversational.maxChars == 45)
    #expect(VideoProfile.lecturing.maxChars == 70)
    #expect(VideoProfile.technical.maxChars == 55)
}

@Test func testProfileNamed() {
    let p = VideoProfile.named(.technical)
    #expect(p.name == .technical)
    #expect(p.boundaryThreshold == VideoProfile.technical.boundaryThreshold)
}
