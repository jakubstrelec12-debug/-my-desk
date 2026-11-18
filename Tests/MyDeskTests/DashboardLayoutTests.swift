import XCTest
@testable import MyDesk

final class DashboardLayoutTests: XCTestCase {
    func testTabletHasNoHorizontalOverflowAndFitsAllColumns() {
        for size in [(1024.0, 720.0), (960.0, 680.0), (1180.0, 820.0)] {
            let layout = DashboardLayout(width: size.0, height: size.1)
            XCTAssertTrue(layout.compact)
            XCTAssertEqual(layout.columns, 3)
            XCTAssertLessThanOrEqual(layout.leftWidth + layout.centerWidth + layout.rightWidth + 2 * layout.gap + 2 * layout.inset, size.0 + 0.01)
            XCTAssertGreaterThanOrEqual(layout.leftWidth, 225)
            XCTAssertGreaterThanOrEqual(layout.centerWidth, 435)
            XCTAssertLessThanOrEqual(layout.contentHeight + layout.headerHeight + layout.gap + 2 * layout.inset, size.1 + 0.01)
        }
    }
    func testPortraitAndNarrowWindowsReflowInsteadOfForcingDesktopWidth() {
        let portrait = DashboardLayout(width: 768, height: 1000)
        XCTAssertEqual(portrait.columns, 2)
        XCTAssertLessThanOrEqual(portrait.leftWidth + portrait.centerWidth + portrait.gap, portrait.contentWidth + 0.01)
        let narrow = DashboardLayout(width: 600, height: 720)
        XCTAssertEqual(narrow.columns, 1)
        XCTAssertEqual(narrow.centerWidth, narrow.contentWidth)
        XCTAssertFalse(DashboardLayout(width: 1480, height: 890).compact)
    }
    func testHidingWidgetsReclaimsTheirSpaceWithoutLeavingBlankPanels() {
        let layout = DashboardLayout(width: 1024, height: 720)
        let weights: [(String, CGFloat)] = [("weather", 0.36), ("news", 0.37), ("system", 0.27)]
        let all = Set(weights.map { $0.0 })
        let total = weights.reduce(CGFloat.zero) { $0 + layout.panelHeight($1.0, weights: weights, visible: all) } + 2 * layout.gap
        XCTAssertEqual(total, layout.contentHeight, accuracy: 0.01)
        XCTAssertEqual(layout.panelHeight("news", weights: weights, visible: ["news"]), layout.contentHeight)
        XCTAssertEqual(layout.panelHeight("weather", weights: weights, visible: ["news"]), 0)
    }
    func testLayoutAndLocationPreferencesPreserveExistingConfiguration() throws {
        var old = Configuration(); old.displayName = "Jakube"; old.microsoft.clientID = "saved-id"
        let original = try JSONEncoder().encode(old)
        var restored = try JSONDecoder().decode(Configuration.self, from: original)
        XCTAssertNil(restored.dashboardLayout); XCTAssertNil(restored.weatherFollowsLocation)
        restored.dashboardLayout = "compact"; restored.weatherFollowsLocation = true
        let saved = try JSONDecoder().decode(Configuration.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(saved.microsoft.clientID, "saved-id"); XCTAssertEqual(saved.displayName, "Jakube")
        XCTAssertEqual(saved.dashboardLayout, "compact"); XCTAssertEqual(saved.weatherFollowsLocation, true)
    }
}
