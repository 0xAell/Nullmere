import AppKit
import SwiftUI
import XCTest
@testable import NullmereKit

/// The panels' buttons clicked with the mouse in a real window: a click
/// reaches a button's action, and a disabled button ignores it.
@MainActor
final class ClickTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    private func spin(_ seconds: Double = 0.15) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    private func host(_ view: some View) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 240, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view.frame(width: 240, height: 80).background(Color.black))
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.contentView?.layoutSubtreeIfNeeded()
        self.window = window
        spin()
        return window
    }

    /// A click at the window's centre, as the mouse makes one.
    private func click(_ window: NSWindow) {
        let centre = NSPoint(x: 120, y: 40)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: centre, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        spin()
    }

    func testAClickReachesAButtonAndADisabledOneIgnoresIt() {
        var pressed = 0
        let enabled = host(QuietButton(title: "Ready", size: 12, prominent: true) { pressed += 1 }.frame(width: 240, height: 80))
        click(enabled)
        XCTAssertEqual(pressed, 1, "The click reaches the button")
        enabled.close()

        let disabled = host(QuietButton(title: "Ready", size: 12, enabled: false) { pressed += 1 }.frame(width: 240, height: 80))
        click(disabled)
        XCTAssertEqual(pressed, 1, "A disabled button ignores the click")
    }
}
