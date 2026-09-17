import SwiftUI
import LingxiCore

@MainActor final class DashboardLayoutStore: ObservableObject {
    @Published private(set) var layout: DashboardLayout
    private let defaults: UserDefaults
    private let key = "dashboardLayout.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        layout = defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(DashboardLayout.self, from: $0) } ?? DashboardLayout()
    }
    func save(_ value: DashboardLayout) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key); layout = value
    }
}
