import Foundation
import Testing
@testable import CodexQuotaCore

@Test func steamIncreasesWithCoffeeAndStaysWithinVisualBounds() {
    let empty = CoffeeSteamStyle(remaining: 0)
    #expect(!empty.isVisible)
    #expect(empty.opacity == 0 && empty.widthFraction == 0 && empty.heightFraction == 0)
    let low = CoffeeSteamStyle(remaining: 10)
    let middle = CoffeeSteamStyle(remaining: 50)
    let full = CoffeeSteamStyle(remaining: 100)
    #expect(low.isVisible)
    #expect(low.opacity < middle.opacity && middle.opacity < full.opacity)
    #expect(low.widthFraction < middle.widthFraction && middle.widthFraction < full.widthFraction)
    #expect(low.heightFraction < middle.heightFraction && middle.heightFraction < full.heightFraction)
    #expect(middle.opacity >= 0.50 && middle.widthFraction >= 0.25 && middle.heightFraction >= 0.35)
    #expect(full.opacity <= 0.90)
    #expect(full.widthFraction <= 0.4 && full.heightFraction <= 0.5)
    var previous = empty
    for percent in 1...100 {
        let next = CoffeeSteamStyle(remaining: Double(percent))
        #expect(next.opacity >= previous.opacity)
        #expect(next.widthFraction >= previous.widthFraction)
        #expect(next.heightFraction >= previous.heightFraction)
        previous = next
    }
}

@Test func steamUsesLiquidBandsAndHidesUnknownReadings() {
    #expect(CoffeeSteamStyle(remaining: 62) == CoffeeSteamStyle(remaining: 60))
    #expect(CoffeeSteamStyle(remaining: 99.9) == CoffeeSteamStyle(remaining: 95))
    #expect(CoffeeSteamStyle(remaining: 200) == CoffeeSteamStyle(remaining: 100))
    for value: Double? in [nil, .nan, .infinity, -.infinity, -10] {
        #expect(!CoffeeSteamStyle(remaining: value).isVisible)
    }
}


@Test func coffeeBandsMatchApprovedBoundaries() {
    let bands: [(ClosedRange<Int>, Int)] = [
        (0...0, 0), (1...5, 5), (6...14, 10), (15...24, 20), (25...34, 30),
        (35...44, 40), (45...54, 50), (55...64, 60), (65...74, 70),
        (75...84, 80), (85...94, 90), (95...99, 95), (100...100, 100)
    ]
    for (range, expected) in bands {
        for value in range {
            #expect(CoffeeLevel.heightPercent(for: Double(value)) == expected)
        }
    }
    #expect(Set((0...100).compactMap { CoffeeLevel.heightPercent(for: Double($0)) }).count == 13)
    #expect(CoffeeLevel.displayedPercent(62.9) == 62)
    #expect(CoffeeLevel.heightPercent(for: 62.9) == 60)
    #expect(CoffeeLevel.heightPercent(for: 99.99) == 95)
}

@Test func unknownCoffeeIsNotAnEmptyCup() {
    for value: Double? in [nil, .nan, .infinity, -.infinity] {
        #expect(CoffeeLevel.heightPercent(for: value) == nil)
        #expect(CoffeeLevel.displayedPercent(value) == nil)
    }
    #expect(CoffeeLevel.heightPercent(for: -10) == 0)
    #expect(CoffeeLevel.heightPercent(for: 120) == 100)
}

@Test func coffeeHeroUsesLimitingCoreWindow() throws {
    let data = Data("""
    {"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":18,"windowDurationMins":300},
    "secondary":{"usedPercent":38,"windowDurationMins":10080}},
    "reserve":{"primary":{"usedPercent":99}}}}
    """.utf8)
    let snapshot = try JSONDecoder().decode(UsageSnapshot.self, from: data)
    #expect(snapshot.core?.displayWindow?.label == "每周")
    #expect(snapshot.core?.displayWindow?.remaining == 62)
    #expect(snapshot.menuBarTitle == "Codex 62%")
    #expect(CoffeeLevel.heightPercent(for: snapshot.core?.displayWindow?.remaining) == 60)
}
