import Foundation
import Testing
@testable import LingxiCore

struct DashboardLayoutTests {
    @Test func restoresOldOrUnknownConfigurationWithoutLosingNewCards() throws {
        let data = Data(#"{"order":["agenda","agenda","retired"],"hidden":["notes","retired"]}"#.utf8)
        let layout = try JSONDecoder().decode(DashboardLayout.self, from: data)
        #expect(layout.order.first == .agenda)
        #expect(layout.order.count == DashboardComponent.allCases.count)
        #expect(layout.visible.contains(.milestones))
        #expect(!layout.visible.contains(.notes))
        #expect(try JSONDecoder().decode(DashboardLayout.self, from: JSONEncoder().encode(layout)) == layout)
    }
    @Test func movingAndHidingAreIndependentAndKeepOneVisibleCard() {
        var layout = DashboardLayout()
        layout.move(.agenda, before: .hexagram)
        #expect(layout.order.first == .agenda)
        layout.move(.notes, by: -1)
        #expect(layout.order[4] == .notes)
        for item in DashboardComponent.allCases where item != .agenda { let hidden = layout.setVisible(false, for: item); #expect(hidden) }
        let refused = layout.setVisible(false, for: .agenda)
        #expect(!refused)
        #expect(layout.visible == [.agenda])
        let shown = layout.setVisible(true, for: .notes)
        #expect(shown)
        #expect(layout.visible == [.agenda, .notes])
    }
    @Test func corruptAllHiddenConfigurationRecoversAUsableDashboard() {
        let layout = DashboardLayout(hidden: Set(DashboardComponent.allCases))
        #expect(layout.visible.count == DashboardComponent.allCases.count)
        #expect(DashboardLayout.agendaFirst.order.prefix(2) == [.agenda, .milestones])
    }
}
