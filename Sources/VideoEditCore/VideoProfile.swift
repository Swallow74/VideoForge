public enum ProfileName: String, Sendable, Codable {
    case conversational
    case lecturing
    case technical
}

public struct VideoProfile: Sendable, Codable {
    public let name: ProfileName
    public let boundaryThreshold: Float
    public let maxChars: Int
    public let maxDuration: Double
    public let weakConjBoost: Float
    public let gapBreak: Double

    public init(
        name: ProfileName,
        boundaryThreshold: Float,
        maxChars: Int,
        maxDuration: Double,
        weakConjBoost: Float,
        gapBreak: Double
    ) {
        self.name = name
        self.boundaryThreshold = boundaryThreshold
        self.maxChars = maxChars
        self.maxDuration = maxDuration
        self.weakConjBoost = weakConjBoost
        self.gapBreak = gapBreak
    }

    public static let conversational = VideoProfile(
        name: .conversational,
        boundaryThreshold: 0.55,
        maxChars: 45,
        maxDuration: 8.0,
        weakConjBoost: 1.3,
        gapBreak: 0.8
    )

    public static let lecturing = VideoProfile(
        name: .lecturing,
        boundaryThreshold: 0.70,
        maxChars: 70,
        maxDuration: 10.0,
        weakConjBoost: 0.8,
        gapBreak: 1.3
    )

    public static let technical = VideoProfile(
        name: .technical,
        boundaryThreshold: 0.62,
        maxChars: 55,
        maxDuration: 9.0,
        weakConjBoost: 1.0,
        gapBreak: 1.0
    )

    public static let all: [VideoProfile] = [.conversational, .lecturing, .technical]

    public static func named(_ name: ProfileName) -> VideoProfile {
        switch name {
        case .conversational: return .conversational
        case .lecturing: return .lecturing
        case .technical: return .technical
        }
    }
}
