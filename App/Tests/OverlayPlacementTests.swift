import XCTest
@testable import Grains

final class OverlayPlacementTests: XCTestCase {
    func testCardCenteredWithTopAt22Percent() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let origin = OverlayPlacement.cardOrigin(screen: screen, visible: visible)
        XCTAssertEqual(origin.x, (1512 - 640) / 2)
        XCTAssertEqual(origin.y, (982 - 982 * 0.22).rounded())
    }

    func testPanelFrameWrapsCardWithMargins() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = OverlayPlacement.panelFrame(screen: screen, visible: screen)
        let m = OverlayPlacement.margins
        XCTAssertEqual(frame.width, 640 + 2 * m.horizontal)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
        // The card's top edge sits `m.top` below the panel's top.
        XCTAssertEqual(frame.maxY - m.top, (982 - 982 * 0.22).rounded())
    }

    func testSecondaryScreenWithOffsetOrigin() {
        let screen = CGRect(x: -1920, y: 200, width: 1920, height: 1080)
        let origin = OverlayPlacement.cardOrigin(screen: screen, visible: screen)
        XCTAssertEqual(origin.x, -1920 + (1920 - 640) / 2)
        XCTAssertEqual(origin.y, (200 + 1080 - 1080 * 0.22).rounded())
    }

    func testTopClampedBelowMenuBar() {
        let screen = CGRect(x: 0, y: 0, width: 800, height: 100)
        let visible = CGRect(x: 0, y: 0, width: 800, height: 60)
        XCTAssertLessThanOrEqual(OverlayPlacement.cardOrigin(screen: screen, visible: visible).y, 60)
    }

    func testScreenContainingPointer() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 100, y: 0, width: 100, height: 100)
        XCTAssertEqual(OverlayPlacement.screen(containing: CGPoint(x: 150, y: 50), in: [a, b]), b)
        // The very top edge (y == maxY) still belongs to the screen.
        XCTAssertEqual(OverlayPlacement.screen(containing: CGPoint(x: 150, y: 100), in: [a, b]), b)
        XCTAssertEqual(OverlayPlacement.screen(containing: CGPoint(x: 999, y: 999), in: [a, b]), a)
    }
}

final class CornerZoneTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)

    func testZones() {
        XCTAssertTrue(CornerZone.contains(CGPoint(x: 0, y: 800), corner: .topLeft, of: screen))
        XCTAssertTrue(CornerZone.contains(CGPoint(x: 11, y: 789), corner: .topLeft, of: screen))
        XCTAssertFalse(CornerZone.contains(CGPoint(x: 12, y: 799), corner: .topLeft, of: screen))
        XCTAssertTrue(CornerZone.contains(CGPoint(x: 999, y: 0), corner: .bottomRight, of: screen))
        XCTAssertFalse(CornerZone.contains(CGPoint(x: 999, y: 0), corner: .bottomLeft, of: screen))
        XCTAssertTrue(CornerZone.contains(CGPoint(x: 1000, y: 800), corner: .topRight, of: screen))
    }

    func testSystemHotCornersSkipZeroAndOne() {
        let prefs: [String: Any] = ["wvous-tl-corner": NSNumber(value: 2), "wvous-tr-corner": NSNumber(value: 1), "wvous-bl-corner": NSNumber(value: 0)]
        XCTAssertEqual(CornerZone.systemHotCorners(dockPreferences: prefs), [.topLeft])
    }
}
