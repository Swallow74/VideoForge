import Testing
import Foundation
@testable import VideoEditCore

@Test func testFormatTimestamp() {
    let ts = SRTExporter.formatTimestamp(3661.500)
    #expect(ts == "01:01:01,500")
}

@Test func testFormatTimestampZero() {
    let ts = SRTExporter.formatTimestamp(0)
    #expect(ts == "00:00:00,000")
}

@Test func testFormatTimestampNoLeadingZeros() {
    let ts = SRTExporter.formatTimestamp(65.010)
    #expect(ts == "00:01:05,010")
}

@Test func testWrapTextShort() {
    let result = SRTExporter.wrapText("Ciao mondo")
    #expect(result == "Ciao mondo")
}

@Test func testWrapTextLong() {
    let long = (0..<20).map { _ in "parola" }.joined(separator: " ")
    let result = SRTExporter.wrapText(long, maxChars: 42)
    let lines = result.split(separator: "\n")
    #expect(lines.count <= 3)
    for line in lines {
        #expect(line.count <= 42)
    }
}

@Test func testSplitByCPS_UnderLimit() {
    let seg = Segment(start: 0, end: 10.0, text: "Frase breve")
    let result = SRTExporter.splitByCPS(seg)
    #expect(result.count == 1)
    #expect(result[0].text == "Frase breve")
}

@Test func testSplitByCPS_OverLimit() {
    let longText = "Prima parte della frase che finisce qui. Seconda parte che continua oltre il limite di caratteri al secondo"
    let seg = Segment(start: 0, end: 5.0, text: longText)
    let result = SRTExporter.splitByCPS(seg)
    #expect(result.count == 2)
    #expect(result[0].start == 0)
    #expect(result[1].end == 5.0)
    #expect(result[0].end > result[0].start)
    #expect(result[1].end > result[1].start)
    #expect(result[0].text.contains("qui"))
    #expect(result[1].text.contains("Seconda"))
}

@Test func testSplitByCPS_NoPunct() {
    let seg = Segment(start: 0, end: 2.0, text: "Frase senza punteggiatura ma molto lunga per testare limite caratteri al secondo")
    let result = SRTExporter.splitByCPS(seg)
    #expect(result.count == 1, "Should not split if no punctuation")
}

@Test func testSplitByCPS_EdgeTooSmall() {
    let seg = Segment(start: 0, end: 2.0, text: "Piccola. Frase.")
    let result = SRTExporter.splitByCPS(seg)
    #expect(result.count == 1, "Should not split if parts too small")
}

@Test func testValidateSegments() {
    let segs = [
        Segment(start: 5.0, end: 3.0, text: "Errore"),
        Segment(start: 4.0, end: 6.0, text: "Regressione"),
    ]
    let validated = SRTExporter.validateSegments(segs)
    #expect(validated[0].end > validated[0].start)
    #expect(validated[1].start >= validated[0].end)
}

@Test func testExportSRT() {
    let segs = [
        Segment(start: 0, end: 2.5, text: "Ciao mondo."),
        Segment(start: 2.5, end: 5.0, text: "Come stai?"),
    ]

    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(UUID().uuidString).srt")
    try! SRTExporter.exportSRT(segs, to: tmp.path)

    let content = try! String(contentsOf: tmp, encoding: .utf8)
    #expect(content.contains("00:00:00,000 --> 00:00:02,500"))
    #expect(content.contains("Ciao mondo."))
    #expect(content.contains("Come stai?"))
    #expect(content.contains("1\n"))
    #expect(content.contains("2\n"))

    try? FileManager.default.removeItem(at: tmp)
}

@Test func testFinoAPocoFix() {
    let segs = [
        Segment(start: 0, end: 3.0, text: "fino a poco"),
    ]
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("test-fix-\(UUID().uuidString).srt")
    try! SRTExporter.exportSRT(segs, to: tmp.path)

    let content = try! String(contentsOf: tmp, encoding: .utf8)
    #expect(content.contains("fino a poco tempo fa"))

    try? FileManager.default.removeItem(at: tmp)
}