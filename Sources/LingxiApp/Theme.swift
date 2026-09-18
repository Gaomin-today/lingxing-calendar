import SwiftUI
import LingxiCore

enum Theme {
    static let paper = Color(hex: 0xF8F6F0)
    static let ink = Color(hex: 0x283F38)
    static let secondary = Color(hex: 0x626F64)
    static let vermilion = Color(hex: 0xA1503F)
    // Neutral paper and semantic warnings stay stable; only the two chosen accents tint surfaces.
    static var jade: Color { AppearanceStore.shared.primaryColor }
    static var accent: Color { AppearanceStore.shared.accentColor }
    static var panel: Color { tint(AppearanceStore.shared.preferences.primary, amount: 0.92) }
    static var softJade: Color { tint(AppearanceStore.shared.preferences.primary, amount: 0.87) }
    static var softAccent: Color { tint(AppearanceStore.shared.preferences.secondary ?? AppearanceStore.shared.preferences.primary, amount: 0.89) }
    static var card: Color { tint(AppearanceStore.shared.preferences.secondary ?? AppearanceStore.shared.preferences.primary, amount: 0.985) }
    static var line: Color { tint(AppearanceStore.shared.preferences.secondary ?? AppearanceStore.shared.preferences.primary, amount: 0.78) }
    private static func tint(_ color: AppearanceColor, amount: Double) -> Color {
        Color(appearance: color.mixed(with: AppearanceColor(hex: 0xFFFEFA), amount: amount))
    }
}

extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
struct Pill: View {
    var text: String
    var color: Color? = nil
    @ObservedObject private var appearance = AppearanceStore.shared
    private var effectiveColor: Color { color ?? appearance.primaryColor }
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(effectiveColor).background(effectiveColor.opacity(0.09), in: Capsule()) }
}
struct QuietButton: ButtonStyle {
    @ObservedObject private var appearance = AppearanceStore.shared
    func makeBody(configuration: Configuration) -> some View {
        let _ = appearance.preferences
        return configuration.label.padding(.horizontal, 12).padding(.vertical, 8).background(configuration.isPressed ? Theme.line : Theme.card, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1)).foregroundStyle(Theme.ink).contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
struct JadeButton: ButtonStyle {
    @ObservedObject private var appearance = AppearanceStore.shared
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(.white).background(appearance.primaryColor.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9)).contentShape(RoundedRectangle(cornerRadius: 9)) }
}
struct SidebarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SidebarButtonBody(content: configuration.label, pressed: configuration.isPressed)
    }
    private struct SidebarButtonBody<Content: View>: View {
        let content: Content
        let pressed: Bool
        @State private var hovering = false
        var body: some View {
            content.background(Theme.jade.opacity(pressed ? 0.13 : hovering ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 9))
                .onHover { hovering = $0 }
        }
    }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    @ObservedObject private var appearance = AppearanceStore.shared
    var body: some View {
        let _ = appearance.preferences
        content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line.opacity(0.65), lineWidth: 1))
    }
}
