import Foundation

public enum DashboardComponent: String, CaseIterable, Codable, Identifiable, Sendable {
    case hexagram, personalDay, agenda, preparation, milestones, notes
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .hexagram: return "我的今日卦"
        case .personalDay: return "这一天，与你"
        case .agenda: return "日程与待办"
        case .preparation: return "准备建议"
        case .milestones: return "倒计时与纪念日"
        case .notes: return "日笺"
        }
    }
    public var symbol: String {
        switch self {
        case .hexagram: return "hexagon"
        case .personalDay: return "sun.horizon"
        case .agenda: return "calendar"
        case .preparation: return "leaf"
        case .milestones: return "hourglass"
        case .notes: return "book.pages"
        }
    }
}

/// Presentation preferences only; hiding a card never deletes its underlying data.
public struct DashboardLayout: Codable, Equatable, Sendable {
    public private(set) var order: [DashboardComponent]
    public private(set) var hidden: Set<DashboardComponent>
    public var visible: [DashboardComponent] { order.filter { !hidden.contains($0) } }
    public init(order: [DashboardComponent] = DashboardComponent.allCases, hidden: Set<DashboardComponent> = []) {
        var seen = Set<DashboardComponent>()
        self.order = (order + DashboardComponent.allCases).filter { seen.insert($0).inserted }
        self.hidden = hidden.count < DashboardComponent.allCases.count ? hidden : []
    }
    public mutating func move(_ item: DashboardComponent, before destination: DashboardComponent) {
        guard item != destination, let from = order.firstIndex(of: item), let to = order.firstIndex(of: destination) else { return }
        order.remove(at: from)
        order.insert(item, at: min(to, order.count))
    }
    public mutating func move(_ item: DashboardComponent, by offset: Int) {
        guard let from = order.firstIndex(of: item), order.indices.contains(from + offset) else { return }
        order.swapAt(from, from + offset)
    }
    @discardableResult public mutating func setVisible(_ value: Bool, for component: DashboardComponent) -> Bool {
        if value { hidden.remove(component); return true }
        guard visible.count > 1 || hidden.contains(component) else { return false }
        hidden.insert(component); return true
    }
    public static var agendaFirst: DashboardLayout {
        DashboardLayout(order: [.agenda, .milestones, .hexagram, .personalDay, .preparation, .notes])
    }
    private enum CodingKeys: String, CodingKey { case order, hidden }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let order = try container.decodeIfPresent([String].self, forKey: .order) ?? []
        let hidden = try container.decodeIfPresent([String].self, forKey: .hidden) ?? []
        self.init(order: order.compactMap(DashboardComponent.init(rawValue:)), hidden: Set(hidden.compactMap(DashboardComponent.init(rawValue:))))
    }
}
