import Testing
import Foundation
@testable import VideoEditCore

@Test func testMergeEmpty() {
    let result = MergeService.mergeAndGroup([], profile: .conversational)
    #expect(result.isEmpty)
}

@Test func testMergeSingle() {
    let segs = [Segment(start: 0, end: 2.0, text: "Ciao mondo")]
    let result = MergeService.mergeAndGroup(segs, profile: .conversational)
    #expect(result.count == 1)
    #expect(result[0].text == "Ciao mondo")
    #expect(result[0].start == 0)
    #expect(result[0].end == 2.0)
}

@Test func testMergeJoinsShort() {
    let segs = [
        Segment(start: 0, end: 1.0, text: "Ciao"),
        Segment(start: 1.0, end: 2.0, text: "mondo"),
    ]
    let result = MergeService.mergeAndGroup(segs, profile: .conversational)
    #expect(result.count == 1)
    #expect(result[0].text == "Ciao mondo")
    #expect(result[0].start == 0)
    #expect(result[0].end == 2.0)
}

@Test func testMergeSplitsLong() {
    let segs = (0..<20).map { i in
        Segment(start: Double(i), end: Double(i + 1), text: "parola")
    }
    let result = MergeService.mergeAndGroup(segs, profile: .conversational)
    #expect(result.count > 1, "Should split into multiple groups")
    for seg in result {
        #expect(seg.end - seg.start <= 8.0, "Duration should not exceed max")
    }
}

@Test func testMergeSkipsLoop() {
    let segs = [
        Segment(start: 0, end: 1.0, text: "la la la la"),
        Segment(start: 1.0, end: 2.0, text: "la la la la"),
        Segment(start: 2.0, end: 3.0, text: "la la la la"),
    ]
    let result = MergeService.mergeAndGroup(segs, profile: .conversational)
    #expect(result.count == 0, "Loop segments should be filtered out")
}

@Test func testMergeProfileAware() {
    // Combined 61 chars: exceeds conv maxChars(45) but not lecturing maxChars(70)
    // Duration 9.5s: exceeds conv maxDuration(8) but not lecturing maxDuration(10)
    let segs: [Segment] = [
        Segment(start: 0, end: 4.0, text: "Prima parte breve"),
        Segment(start: 4.0, end: 9.5, text: "seconda parte di media lunghezza per test"),
    ]
    let convResult = MergeService.mergeAndGroup(segs, profile: .conversational)
    #expect(convResult.count == 2, "Conversational profile should split")

    let lectResult = MergeService.mergeAndGroup(segs, profile: .lecturing)
    #expect(lectResult.count == 1, "Lecturing profile should keep together")
}

@Test func testMergeDurationRespected() {
    let profile = VideoProfile.conversational
    let segs: [Segment] = [
        Segment(start: 0, end: 4.0, text: "Frase"),
        Segment(start: 4.0, end: 8.5, text: "lunga"),
    ]
    let result = MergeService.mergeAndGroup(segs, profile: profile)
    // Duration from buffer start (0) to seg end (8.5) = 8.5 > 8.0 max
    #expect(result.count == 2, "Should split when duration exceeds max")
}
