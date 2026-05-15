import Foundation
import SwiftUI

/// Teleprompter state management.
@Observable
public final class TeleprompterService {
    public var text: String = ""
    public var speed: Double = 60  // words per minute
    public var fontSize: Double = 32
    public var isPlaying = false
    public var scrollOffset: Double = 0
    public var textColor: Color = .white
    public var backgroundColor: Color = .black
    public var opacity: Double = 0.8

    public init() {}

    public var totalDuration: Double {
        let wordCount = text.split(separator: " ").count
        return Double(wordCount) / (speed / 60)
    }

    public func loadScript(_ script: String) {
        text = script
        scrollOffset = 0
    }
}