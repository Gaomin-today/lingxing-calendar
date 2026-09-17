import Foundation
import Testing
@testable import LingxiCore

struct AppearancePreferencesTests {
    @Test func customColorsAreStrictAndRoundTrip() throws {
        #expect(AppearanceColor(hexString: " #a0B1c2 ")?.hex == 0xA0B1C2)
        #expect(AppearanceColor(hexString: "123456")?.hexString == "#123456")
        for invalid in ["#fff", "##123456", "#12345678", "#１２３４５６", "#12gg34", "12345\n6"] {
            #expect(AppearanceColor(hexString: invalid) == nil)
        }
        let color = AppearanceColor(hex: 0xFF00AB)
        #expect(try JSONDecoder().decode(AppearanceColor.self, from: JSONEncoder().encode(color)) == color)
        #expect(throws: (any Error).self) { try JSONDecoder().decode(AppearanceColor.self, from: Data("16777216".utf8)) }
    }

    @Test func veryLightAndDarkColorsKeepReadableControlsAndSurfaces() {
        let white = AppearanceColor(hex: 0xFFFFFF), paper = AppearanceColor(hex: 0xF8F6F0), ink = AppearanceColor(hex: 0x283F38)
        let examples: [UInt32] = [0, 0xFFFFFF, 0xFFFF00, 0x00FFFF, 0xFF00FF, 0xFF0000, 0x00FF00, 0x0000FF, 0xF8F6F0]
        for hex in examples + AppearanceElement.allCases.map(\.color.hex) {
            let chosen = AppearanceColor(hex: hex), accent = chosen.readableAccent
            #expect(accent.contrast(with: white) >= 5.3)
            #expect(accent.contrast(with: paper) >= 4.5)
            for amount in [0.87, 0.89, 0.92, 0.985] {
                #expect(chosen.mixed(with: AppearanceColor(hex: 0xFFFEFA), amount: amount).contrast(with: ink) >= 4.5)
            }
        }
        #expect(AppearanceColor(hex: 0).readableAccent.hex == 0)
    }

    @Test func preferencesAllowAtMostTwoDistinctElementsIncludingDecodedFiles() throws {
        var value = AppearancePreferences(preferredElements: [.wood, .wood, .water, .fire])
        #expect(value.preferredElements == [.wood, .water])
        let refusedThird = value.toggleElement(.metal)
        #expect(!refusedThird)
        let removedWood = value.toggleElement(.wood)
        #expect(removedWood)
        let addedMetal = value.toggleElement(.metal)
        #expect(addedMetal)
        #expect(value.preferredElements == [.water, .metal])
        let data = Data(#"{"primary":4155478,"spirit":"sprout","preferredElements":["earth","earth","metal","water"]}"#.utf8)
        #expect(try JSONDecoder().decode(AppearancePreferences.self, from: data).preferredElements == [.earth, .metal])
    }

    @Test func filteringDoesNotChangePetOrColorAndEmptyPreferencesShowAll() throws {
        var value = AppearancePreferences(primary: .init(hex: 0x123456), secondary: .init(hex: 0xABCDEF), spirit: .sprout)
        #expect(value.matchingSpirits.count == 6)
        value.toggleElement(.water)
        #expect(value.matchingSpirits == [.tortoise])
        #expect(value.spirit == .sprout)
        #expect(value.primary.hex == 0x123456)
        #expect(value.secondary?.hex == 0xABCDEF)
        #expect(try JSONDecoder().decode(AppearancePreferences.self, from: JSONEncoder().encode(value)) == value)
        value.clearElements()
        #expect(value.matchingSpirits == SpiritAppearance.allCases)
        value.secondary = nil
        #expect(value.accent == value.primaryAccent)
    }
}
