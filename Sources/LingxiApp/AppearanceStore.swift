import AppKit
import SwiftUI
import LingxiCore

final class AppearanceStore: ObservableObject {
    static let shared = AppearanceStore()
    @Published private(set) var preferences: AppearancePreferences
    private let defaults: UserDefaults
    private let key = "appearancePreferences.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(AppearancePreferences.self, from: data) {
            preferences = value
        } else { preferences = .default }
    }
    func update(_ mutation: (inout AppearancePreferences) -> Void) {
        var value = preferences
        mutation(&value)
        guard value != preferences, let data = try? JSONEncoder().encode(value) else { return }
        preferences = value
        defaults.set(data, forKey: key)
    }
    func reset() { update { $0 = .default } }
    var primaryColor: Color { Color(appearance: preferences.primaryAccent) }
    var accentColor: Color { Color(appearance: preferences.accent) }
}

extension Color {
    init(appearance: AppearanceColor) { self.init(red: appearance.red, green: appearance.green, blue: appearance.blue) }
    var appearanceColor: AppearanceColor? {
        guard let color = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        func byte(_ value: CGFloat) -> UInt32 { UInt32((min(1, max(0, value)) * 255).rounded()) }
        return AppearanceColor(hex: (byte(color.redComponent) << 16) | (byte(color.greenComponent) << 8) | byte(color.blueComponent))
    }
}
