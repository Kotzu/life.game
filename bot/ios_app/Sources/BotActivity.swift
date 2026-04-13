import ActivityKit
import Foundation

/// Atributele pentru Live Activity (Dynamic Island + Lock Screen).
struct BotActivityAttributes: ActivityAttributes {
    typealias ContentState = Status

    struct Status: Codable, Hashable {
        var action:      String
        var displayText: String
        var gold:        Int?
        var hp:          Int?
        var confidence:  Double
        var isAnalyzing: Bool
    }

    let game: String
}
