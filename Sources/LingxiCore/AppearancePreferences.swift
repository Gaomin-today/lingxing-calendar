import Foundation

/// Appearance choices are personal preferences, independent of a chart's interpretation.
public enum AppearanceElement: String, Codable, CaseIterable, Identifiable, Sendable {
    case wood, fire, earth, metal, water
    public var id: String { rawValue }
    public var label: String {
        switch self { case .wood: "木"; case .fire: "火"; case .earth: "土"; case .metal: "金"; case .water: "水" }
    }
    public var color: AppearanceColor {
        switch self {
        case .wood: AppearanceColor(hex: 0x3F6856)
        case .fire: AppearanceColor(hex: 0xAD6652)
        case .earth: AppearanceColor(hex: 0x92723D)
        case .metal: AppearanceColor(hex: 0x7C748D)
        case .water: AppearanceColor(hex: 0x426F89)
        }
    }
    public var colorName: String {
        switch self { case .wood: "松绿"; case .fire: "朱砂"; case .earth: "赭石"; case .metal: "银紫"; case .water: "黛蓝" }
    }
}

public enum SpiritAppearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case sprout, incense, twinCups, lotus, tortoise, bell
    public var id: String { rawValue }
    public var name: String {
        switch self { case .sprout: "青芽"; case .incense: "云炉"; case .twinCups: "双子"; case .lotus: "莲灯"; case .tortoise: "玄龟"; case .bell: "金铃" }
    }
    public var detail: String {
        switch self {
        case .sprout: "把今天慢慢养成新芽"
        case .incense: "一缕云烟，陪你定心"
        case .twinCups: "一对月牙，接住心事"
        case .lotus: "留一盏温柔的小灯"
        case .tortoise: "稳稳走，也会到达"
        case .bell: "轻轻一响，回到当下"
        }
    }
    public var elements: [AppearanceElement] {
        switch self {
        case .sprout: [.wood]
        case .incense: [.earth, .fire]
        case .twinCups: [.wood, .earth]
        case .lotus: [.fire, .wood]
        case .tortoise: [.water]
        case .bell: [.metal]
        }
    }
    public func matches(_ preferences: [AppearanceElement]) -> Bool {
        preferences.isEmpty || preferences.contains(where: elements.contains)
    }
}

public struct AppearanceColor: Codable, Equatable, Hashable, Sendable {
    public let hex: UInt32
    public init(hex: UInt32) { self.hex = min(hex, 0xFFFFFF) }
    public init?(hexString: String) {
        let value = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard digits.utf8.count == 6, digits.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }),
              let hex = UInt32(digits, radix: 16) else { return nil }
        self.hex = hex
    }
    public var hexString: String { String(format: "#%06X", hex) }
    public var red: Double { Double((hex >> 16) & 255) / 255 }
    public var green: Double { Double((hex >> 8) & 255) / 255 }
    public var blue: Double { Double(hex & 255) / 255 }
    public var luminance: Double {
        func linear(_ value: Double) -> Double { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }
    public func contrast(with other: AppearanceColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }
    public func mixed(with other: AppearanceColor, amount: Double) -> AppearanceColor {
        let fraction = min(1, max(0, amount))
        func component(_ a: Double, _ b: Double) -> UInt32 { UInt32((255 * (a * (1 - fraction) + b * fraction)).rounded()) }
        return AppearanceColor(hex: (component(red, other.red) << 16) | (component(green, other.green) << 8) | component(blue, other.blue))
    }
    /// A single accessible accent works both as a white-text button background and as text on paper.
    public var readableAccent: AppearanceColor {
        let white = AppearanceColor(hex: 0xFFFFFF)
        if contrast(with: white) >= 5.3 { return self }
        for step in 1...100 {
            let candidate = mixed(with: AppearanceColor(hex: 0), amount: Double(step) / 100)
            if candidate.contrast(with: white) >= 5.3 { return candidate }
        }
        return AppearanceColor(hex: 0)
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(UInt32.self)
        guard value <= 0xFFFFFF else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "RGB color is outside the 24-bit range") }
        self.hex = value
    }
    public func encode(to encoder: Encoder) throws { var container = encoder.singleValueContainer(); try container.encode(hex) }
}

public struct AppearancePreferences: Codable, Equatable, Sendable {
    public var primary: AppearanceColor
    public var secondary: AppearanceColor?
    public var spirit: SpiritAppearance
    public private(set) var preferredElements: [AppearanceElement]

    public init(primary: AppearanceColor = AppearanceElement.wood.color, secondary: AppearanceColor? = nil,
                spirit: SpiritAppearance = .sprout, preferredElements: [AppearanceElement] = []) {
        self.primary = primary; self.secondary = secondary; self.spirit = spirit
        self.preferredElements = Self.limit(preferredElements)
    }
    public static let `default` = AppearancePreferences()
    public var accent: AppearanceColor { (secondary ?? primary).readableAccent }
    public var primaryAccent: AppearanceColor { primary.readableAccent }
    public var matchingSpirits: [SpiritAppearance] { SpiritAppearance.allCases.filter { $0.matches(preferredElements) } }
    @discardableResult public mutating func toggleElement(_ element: AppearanceElement) -> Bool {
        if preferredElements.contains(element) { preferredElements.removeAll { $0 == element }; return true }
        guard preferredElements.count < 2 else { return false }
        preferredElements.append(element); return true
    }
    public mutating func clearElements() { preferredElements = [] }
    private static func limit(_ elements: [AppearanceElement]) -> [AppearanceElement] {
        elements.reduce(into: [AppearanceElement]()) { if $0.count < 2 && !$0.contains($1) { $0.append($1) } }
    }
    enum CodingKeys: CodingKey { case primary, secondary, spirit, preferredElements }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(primary: try container.decode(AppearanceColor.self, forKey: .primary),
                  secondary: try container.decodeIfPresent(AppearanceColor.self, forKey: .secondary),
                  spirit: try container.decode(SpiritAppearance.self, forKey: .spirit),
                  preferredElements: try container.decodeIfPresent([AppearanceElement].self, forKey: .preferredElements) ?? [])
    }
}
