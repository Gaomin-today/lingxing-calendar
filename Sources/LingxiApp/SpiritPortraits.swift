import SwiftUI
import LingxiCore

/// Native vector portraits remain crisp and transparent in the floating AppKit panel.
struct SpiritView: View {
    var size: CGFloat = 70
    @ObservedObject private var appearance = AppearanceStore.shared
    var body: some View {
        SpiritPortrait(spirit: appearance.preferences.spirit, size: size,
                       primary: appearance.primaryColor, accent: appearance.accentColor)
    }
}

struct SpiritPortrait: View {
    let spirit: SpiritAppearance
    var size: CGFloat = 80
    var primary: Color = Theme.jade
    var accent: Color = Theme.accent

    var body: some View {
        Canvas { context, canvas in
            let scale = min(canvas.width, canvas.height) / 100
            context.scaleBy(x: scale, y: scale)
            let painter = SpiritPainter(primary: primary, accent: accent)
            painter.draw(spirit, in: &context)
        }
        .frame(width: size, height: size)
        .accessibilityLabel("灵宠" + spirit.name + "，" + spirit.detail)
    }
}

private struct SpiritPainter {
    let primary: Color
    let accent: Color
    private let ink = Color(hex: 0x283F38)
    private let blush = Color(hex: 0xB97161).opacity(0.35)
    private let paper = Color(hex: 0xFFF9E9)

    func draw(_ spirit: SpiritAppearance, in context: inout GraphicsContext) {
        ellipse(CGRect(x: 17, y: 88, width: 66, height: 8), fill: primary.opacity(0.10), in: &context)
        switch spirit {
        case .sprout: sprout(&context)
        case .incense: incense(&context)
        case .twinCups: cups(&context)
        case .lotus: lotus(&context)
        case .tortoise: tortoise(&context)
        case .bell: bell(&context)
        }
    }
    private func fill(_ points: (inout Path) -> Void, color: Color, stroke: Color? = nil, in context: inout GraphicsContext) {
        var path = Path(); points(&path)
        context.fill(path, with: .color(color))
        if let stroke { context.stroke(path, with: .color(stroke), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)) }
    }
    private func line(_ points: (inout Path) -> Void, color: Color, width: CGFloat = 1.8, in context: inout GraphicsContext) {
        var path = Path(); points(&path)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
    private func ellipse(_ rect: CGRect, fill: Color, stroke: Color? = nil, in context: inout GraphicsContext) {
        context.fill(Path(ellipseIn: rect), with: .color(fill))
        if let stroke { context.stroke(Path(ellipseIn: rect), with: .color(stroke), lineWidth: 1.5) }
    }
    private func face(x: CGFloat = 50, y: CGFloat = 57, scale: CGFloat = 1, in context: inout GraphicsContext) {
        for direction: CGFloat in [-1, 1] {
            ellipse(CGRect(x: x + direction * 10 * scale - 1.8 * scale, y: y - 3 * scale, width: 3.6 * scale, height: 5.5 * scale), fill: ink, in: &context)
            ellipse(CGRect(x: x + direction * 17 * scale - 4 * scale, y: y + 5 * scale, width: 8 * scale, height: 3.5 * scale), fill: blush, in: &context)
        }
        line({ p in p.move(to: CGPoint(x: x - 4 * scale, y: y + 7 * scale)); p.addQuadCurve(to: CGPoint(x: x + 4 * scale, y: y + 7 * scale), control: CGPoint(x: x, y: y + 12 * scale)) }, color: ink.opacity(0.8), width: 1.3, in: &context)
    }
    private func sprout(_ c: inout GraphicsContext) {
        ellipse(CGRect(x: 13, y: 26, width: 74, height: 64), fill: paper, stroke: primary.opacity(0.65), in: &c)
        ellipse(CGRect(x: 14, y: 28, width: 72, height: 61), fill: primary.opacity(0.17), in: &c)
        line({ p in p.move(to: CGPoint(x: 49, y: 29)); p.addQuadCurve(to: CGPoint(x: 48, y: 10), control: CGPoint(x: 41, y: 18)) }, color: primary, width: 2.4, in: &c)
        fill({ p in p.move(to: CGPoint(x: 48, y: 16)); p.addQuadCurve(to: CGPoint(x: 71, y: 9), control: CGPoint(x: 57, y: 3)); p.addQuadCurve(to: CGPoint(x: 48, y: 16), control: CGPoint(x: 65, y: 25)) }, color: primary, in: &c)
        ellipse(CGRect(x: 25, y: 38, width: 15, height: 7), fill: .white.opacity(0.55), in: &c)
        face(in: &c)
    }
    private func incense(_ c: inout GraphicsContext) {
        // Three feet, wide handles and a domed lid give the censer a distinct silhouette.
        for x: CGFloat in [31, 64] {
            fill({ p in p.move(to: CGPoint(x: x, y: 74)); p.addLine(to: CGPoint(x: x - 3, y: 88)); p.addQuadCurve(to: CGPoint(x: x + 6, y: 88), control: CGPoint(x: x + 2, y: 92)); p.addLine(to: CGPoint(x: x + 7, y: 75)); p.closeSubpath() }, color: primary, in: &c)
        }
        line({ p in p.move(to: CGPoint(x: 26, y: 47)); p.addCurve(to: CGPoint(x: 25, y: 66), control1: CGPoint(x: 3, y: 34), control2: CGPoint(x: 9, y: 67)); p.move(to: CGPoint(x: 74, y: 47)); p.addCurve(to: CGPoint(x: 75, y: 66), control1: CGPoint(x: 97, y: 34), control2: CGPoint(x: 91, y: 67)) }, color: primary, width: 4.3, in: &c)
        fill({ p in p.move(to: CGPoint(x: 20, y: 44)); p.addLine(to: CGPoint(x: 80, y: 44)); p.addQuadCurve(to: CGPoint(x: 71, y: 77), control: CGPoint(x: 84, y: 66)); p.addQuadCurve(to: CGPoint(x: 29, y: 77), control: CGPoint(x: 50, y: 87)); p.addQuadCurve(to: CGPoint(x: 20, y: 44), control: CGPoint(x: 16, y: 66)); p.closeSubpath() }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 21, y: 45)); p.addLine(to: CGPoint(x: 79, y: 45)); p.addQuadCurve(to: CGPoint(x: 21, y: 45), control: CGPoint(x: 50, y: 10)) }, color: primary.opacity(0.35), stroke: primary, in: &c)
        ellipse(CGRect(x: 46, y: 26, width: 8, height: 6), fill: primary, in: &c)
        line({ p in p.move(to: CGPoint(x: 50, y: 23)); p.addCurve(to: CGPoint(x: 49, y: 6), control1: CGPoint(x: 36, y: 18), control2: CGPoint(x: 65, y: 12)) }, color: accent.opacity(0.55), width: 2.6, in: &c)
        line({ p in p.move(to: CGPoint(x: 42, y: 19)); p.addQuadCurve(to: CGPoint(x: 40, y: 8), control: CGPoint(x: 34, y: 12)) }, color: accent.opacity(0.25), in: &c)
        face(y: 59, scale: 0.83, in: &c)
    }
    private func cups(_ c: inout GraphicsContext) {
        // Wooden crescent divination blocks, each with its own small face.
        fill({ p in p.move(to: CGPoint(x: 39, y: 18)); p.addCurve(to: CGPoint(x: 42, y: 84), control1: CGPoint(x: 0, y: 34), control2: CGPoint(x: 9, y: 76)); p.addQuadCurve(to: CGPoint(x: 39, y: 18), control: CGPoint(x: 20, y: 57)); p.closeSubpath() }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 39, y: 18)); p.addCurve(to: CGPoint(x: 42, y: 84), control1: CGPoint(x: 0, y: 34), control2: CGPoint(x: 9, y: 76)); p.addQuadCurve(to: CGPoint(x: 39, y: 18), control: CGPoint(x: 20, y: 57)); p.closeSubpath() }, color: primary.opacity(0.22), in: &c)
        fill({ p in p.move(to: CGPoint(x: 59, y: 23)); p.addCurve(to: CGPoint(x: 60, y: 89), control1: CGPoint(x: 100, y: 34), control2: CGPoint(x: 94, y: 77)); p.addQuadCurve(to: CGPoint(x: 59, y: 23), control: CGPoint(x: 83, y: 56)); p.closeSubpath() }, color: paper, stroke: accent, in: &c)
        fill({ p in p.move(to: CGPoint(x: 59, y: 23)); p.addCurve(to: CGPoint(x: 60, y: 89), control1: CGPoint(x: 100, y: 34), control2: CGPoint(x: 94, y: 77)); p.addQuadCurve(to: CGPoint(x: 59, y: 23), control: CGPoint(x: 83, y: 56)); p.closeSubpath() }, color: accent.opacity(0.15), in: &c)
        face(x: 23, y: 54, scale: 0.40, in: &c); face(x: 78, y: 58, scale: 0.40, in: &c)
        line({ p in p.move(to: CGPoint(x: 47, y: 13)); p.addLine(to: CGPoint(x: 50, y: 8)); p.addLine(to: CGPoint(x: 53, y: 13)) }, color: accent.opacity(0.6), in: &c)
    }
    private func lotus(_ c: inout GraphicsContext) {
        ellipse(CGRect(x: 25, y: 82, width: 50, height: 8), fill: primary.opacity(0.6), in: &c)
        fill({ p in p.move(to: CGPoint(x: 50, y: 81)); p.addQuadCurve(to: CGPoint(x: 22, y: 28), control: CGPoint(x: 15, y: 67)); p.addQuadCurve(to: CGPoint(x: 50, y: 81), control: CGPoint(x: 55, y: 38)) }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 50, y: 81)); p.addQuadCurve(to: CGPoint(x: 78, y: 28), control: CGPoint(x: 85, y: 67)); p.addQuadCurve(to: CGPoint(x: 50, y: 81), control: CGPoint(x: 45, y: 38)) }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 50, y: 84)); p.addQuadCurve(to: CGPoint(x: 5, y: 51), control: CGPoint(x: 15, y: 87)); p.addQuadCurve(to: CGPoint(x: 50, y: 84), control: CGPoint(x: 39, y: 48)) }, color: primary.opacity(0.6), stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 50, y: 84)); p.addQuadCurve(to: CGPoint(x: 95, y: 51), control: CGPoint(x: 85, y: 87)); p.addQuadCurve(to: CGPoint(x: 50, y: 84), control: CGPoint(x: 61, y: 48)) }, color: primary.opacity(0.6), stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 50, y: 31)); p.addCurve(to: CGPoint(x: 50, y: 84), control1: CGPoint(x: 13, y: 62), control2: CGPoint(x: 37, y: 86)); p.addCurve(to: CGPoint(x: 50, y: 31), control1: CGPoint(x: 63, y: 86), control2: CGPoint(x: 87, y: 62)) }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 51, y: 5)); p.addCurve(to: CGPoint(x: 50, y: 33), control1: CGPoint(x: 39, y: 16), control2: CGPoint(x: 37, y: 29)); p.addCurve(to: CGPoint(x: 51, y: 5), control1: CGPoint(x: 70, y: 28), control2: CGPoint(x: 51, y: 16)) }, color: accent.opacity(0.82), in: &c)
        face(y: 60, scale: 0.8, in: &c)
    }
    private func tortoise(_ c: inout GraphicsContext) {
        for x: CGFloat in [18, 65] { ellipse(CGRect(x: x, y: 69, width: 17, height: 14), fill: primary.opacity(0.75), in: &c) }
        fill({ p in p.move(to: CGPoint(x: 83, y: 65)); p.addLine(to: CGPoint(x: 96, y: 73)); p.addLine(to: CGPoint(x: 81, y: 75)); p.closeSubpath() }, color: primary, in: &c)
        ellipse(CGRect(x: 16, y: 28, width: 70, height: 51), fill: paper, stroke: primary, in: &c)
        ellipse(CGRect(x: 19, y: 29, width: 64, height: 46), fill: primary.opacity(0.25), in: &c)
        line({ p in p.move(to: CGPoint(x: 40, y: 38)); p.addLine(to: CGPoint(x: 60, y: 38)); p.addLine(to: CGPoint(x: 70, y: 51)); p.addLine(to: CGPoint(x: 59, y: 65)); p.addLine(to: CGPoint(x: 41, y: 65)); p.addLine(to: CGPoint(x: 31, y: 51)); p.closeSubpath(); p.move(to: CGPoint(x: 40, y: 38)); p.addLine(to: CGPoint(x: 35, y: 31)); p.move(to: CGPoint(x: 60, y: 38)); p.addLine(to: CGPoint(x: 65, y: 32)); p.move(to: CGPoint(x: 70, y: 51)); p.addLine(to: CGPoint(x: 82, y: 51)); p.move(to: CGPoint(x: 59, y: 65)); p.addLine(to: CGPoint(x: 64, y: 74)) }, color: primary.opacity(0.6), width: 1.4, in: &c)
        ellipse(CGRect(x: 4, y: 54, width: 37, height: 31), fill: paper, stroke: primary, in: &c)
        ellipse(CGRect(x: 7, y: 56, width: 31, height: 26), fill: accent.opacity(0.12), in: &c)
        face(x: 23, y: 66, scale: 0.61, in: &c)
        ellipse(CGRect(x: 41, y: 42, width: 8, height: 4), fill: .white.opacity(0.6), in: &c)
    }
    private func bell(_ c: inout GraphicsContext) {
        ellipse(CGRect(x: 42, y: 8, width: 16, height: 17), fill: .clear, stroke: primary, in: &c)
        line({ p in p.move(to: CGPoint(x: 50, y: 72)); p.addLine(to: CGPoint(x: 50, y: 86)) }, color: accent, width: 2, in: &c)
        ellipse(CGRect(x: 44, y: 81, width: 12, height: 10), fill: accent, in: &c)
        fill({ p in p.move(to: CGPoint(x: 17, y: 74)); p.addQuadCurve(to: CGPoint(x: 28, y: 39), control: CGPoint(x: 30, y: 60)); p.addCurve(to: CGPoint(x: 72, y: 39), control1: CGPoint(x: 27, y: 8), control2: CGPoint(x: 73, y: 8)); p.addQuadCurve(to: CGPoint(x: 83, y: 74), control: CGPoint(x: 70, y: 60)); p.addQuadCurve(to: CGPoint(x: 17, y: 74), control: CGPoint(x: 50, y: 85)) }, color: paper, stroke: primary, in: &c)
        fill({ p in p.move(to: CGPoint(x: 17, y: 74)); p.addQuadCurve(to: CGPoint(x: 28, y: 39), control: CGPoint(x: 30, y: 60)); p.addCurve(to: CGPoint(x: 72, y: 39), control1: CGPoint(x: 27, y: 8), control2: CGPoint(x: 73, y: 8)); p.addQuadCurve(to: CGPoint(x: 83, y: 74), control: CGPoint(x: 70, y: 60)); p.addQuadCurve(to: CGPoint(x: 17, y: 74), control: CGPoint(x: 50, y: 85)) }, color: primary.opacity(0.18), in: &c)
        line({ p in p.move(to: CGPoint(x: 20, y: 72)); p.addQuadCurve(to: CGPoint(x: 80, y: 72), control: CGPoint(x: 50, y: 79)) }, color: primary.opacity(0.6), width: 2, in: &c)
        line({ p in p.move(to: CGPoint(x: 35, y: 36)); p.addQuadCurve(to: CGPoint(x: 43, y: 27), control: CGPoint(x: 36, y: 29)) }, color: .white.opacity(0.8), width: 3, in: &c)
        face(y: 49, scale: 0.86, in: &c)
    }
}
