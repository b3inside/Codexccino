import Foundation

/// Shared by the menu-bar readout and the coffee renderer. Unknown is distinct from empty.
public enum CoffeeLevel {
    public static func displayedPercent(_ remaining: Double?) -> Int? {
        guard let remaining, remaining.isFinite else { return nil }
        return Int(min(100, max(0, remaining)).rounded(.down))
    }

    public static func heightPercent(for remaining: Double?) -> Int? {
        guard let value = displayedPercent(remaining) else { return nil }
        switch value {
        case 0: return 0
        case 1...5: return 5
        case 6...14: return 10
        case 95...99: return 95
        case 100: return 100
        default: return ((value + 5) / 10) * 10
        }
    }
}

/// A visual cue for the coffee metaphor, driven by the same thirteen liquid
/// levels. Empty and unknown readings never emit steam.
public struct CoffeeSteamStyle: Sendable, Equatable {
    public let opacity: Double
    public let widthFraction: Double
    public let heightFraction: Double
    public var isVisible: Bool { opacity > 0 }

    public init(remaining: Double?) {
        let amount = Double(CoffeeLevel.heightPercent(for: remaining) ?? 0) / 100
        opacity = amount > 0 ? 0.20 + 0.64 * amount : 0
        widthFraction = amount > 0 ? 0.14 + 0.24 * amount : 0
        heightFraction = amount > 0 ? 0.26 + 0.22 * amount : 0
    }
}

extension UsageBucket {
    /// The hero always represents the most constrained core window, like the menu bar.
    public var displayWindow: UsageWindow? {
        windows.filter { $0.remaining != nil }.min { $0.remaining! < $1.remaining! }
    }
}
