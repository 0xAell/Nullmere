import AppKit
import XCTest
@testable import NullmereKit

/// The window fitted to a screen too small for it.
@MainActor
final class WindowFitterTests: XCTestCase {
    func testAWindowTooLargeForItsScreenIsFittedToIt() throws {
        let screen = try XCTUnwrap(NSScreen.main ?? NSScreen.screens.first, "A screen")
        let visible = screen.visibleFrame
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: visible.width + 400, height: visible.height + 300),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false, screen: screen)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: window.contentLayoutRect)
        window.contentView = content
        defer { window.close() }
        // Not yet on screen, so AppKit hasn't fitted it itself.
        window.setFrame(NSRect(x: 0, y: 0, width: visible.width + 400, height: visible.height + 300), display: false)
        XCTAssertGreaterThan(window.frame.width, visible.width, "Too large to begin with")
        content.addSubview(WindowFitterView())
        let deadline = Date().addingTimeInterval(3)
        while window.frame.width > visible.width, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        XCTAssertLessThanOrEqual(window.frame.width, visible.width)
        XCTAssertLessThanOrEqual(window.frame.height, visible.height)
    }
}
