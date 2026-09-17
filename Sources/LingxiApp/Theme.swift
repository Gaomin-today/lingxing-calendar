import SwiftUI

enum Theme {
    static let paper = Color(hex: 0xF8F6F0)
    static let panel = Color(hex: 0xEFEEE5)
    static let card = Color(hex: 0xFFFEFA)
    static let ink = Color(hex: 0x283F38)
    static let secondary = Color(hex: 0x7C8275)
    static let jade = Color(hex: 0x3F6856)
    static let softJade = Color(hex: 0xE6ECE1)
    static let vermilion = Color(hex: 0xAD6652)
    static let line = Color(hex: 0xDFE2D5)
}
extension Color {
    init(hex: UInt) { self.init(red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255) }
}
struct Pill: View {
    var text: String
    var color: Color = Theme.jade
    var body: some View { Text(text).font(.system(size: 10, weight: .medium)).padding(.horizontal, 8).padding(.vertical, 4).foregroundStyle(color).background(color.opacity(0.09), in: Capsule()) }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.padding(.horizontal, 12).padding(.vertical, 8).background(configuration.isPressed ? Theme.line : Theme.card, in: RoundedRectangle(cornerRadius: 9)).overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.line, lineWidth: 1)).foregroundStyle(Theme.ink) }
}
struct JadeButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10).foregroundStyle(.white).background(Theme.jade.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 9)) }
}
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { content.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(Theme.card, in: RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line.opacity(0.65), lineWidth: 1)) }
}
struct SpiritView: View {
    var size: CGFloat = 70
    var body: some View {
        ZStack {
            Ellipse().fill(Theme.jade.opacity(0.09)).frame(width: size * 0.77, height: size * 0.16).offset(y: size * 0.45)
            Ellipse().fill(Color(hex: 0xE3ECD8)).frame(width: size * 0.83, height: size * 0.78).overlay(Ellipse().stroke(Theme.jade.opacity(0.35), lineWidth: 1.5)).offset(y: size * 0.04)
            Ellipse().fill(Theme.jade).frame(width: size * 0.23, height: size * 0.11).rotationEffect(.degrees(-35)).offset(x: size * 0.07, y: -size * 0.39)
            Path { p in p.move(to: CGPoint(x: size * 0.50, y: size * 0.21)); p.addQuadCurve(to: CGPoint(x: size * 0.49, y: size * 0.05), control: CGPoint(x: size * 0.41, y: size * 0.12)) }.stroke(Theme.jade, lineWidth: 2)
            HStack(spacing: size * 0.20) { Capsule().fill(Theme.ink).frame(width: size * 0.045, height: size * 0.075); Capsule().fill(Theme.ink).frame(width: size * 0.045, height: size * 0.075) }.offset(y: size * 0.015)
            HStack(spacing: size * 0.36) { Ellipse().fill(Theme.vermilion.opacity(0.28)).frame(width: size * 0.10, height: size * 0.045); Ellipse().fill(Theme.vermilion.opacity(0.28)).frame(width: size * 0.10, height: size * 0.045) }.offset(y: size * 0.075)
            Path { p in p.move(to: CGPoint(x: size * 0.46, y: size * 0.56)); p.addQuadCurve(to: CGPoint(x: size * 0.54, y: size * 0.56), control: CGPoint(x: size * 0.50, y: size * 0.61)) }.stroke(Theme.ink.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }.frame(width: size, height: size).accessibilityLabel("阿灵，一只长着嫩芽的青绿色小精灵")
    }
}
