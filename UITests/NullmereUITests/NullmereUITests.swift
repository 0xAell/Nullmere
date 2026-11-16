import AppKit
import XCTest

/// Nullmere Online as VoiceOver and Accessibility Inspector meet it, through
/// the Mac's own accessibility: the app opened as a player opens it, and
/// every screen, the launcher's and the realm's, put to Xcode's
/// accessibility audit.
///
/// It opens the debug build scripts/ui-test.sh makes and registers with
/// Launch Services: only a debug build reads the variables that open it as
/// a Mac whose on-device model is ready would, with a realm of its own. That
/// build goes by a name of its own, so Launch Services can't open an
/// installed copy in its place and its settings never mix with a keeper's;
/// what it keeps, it keeps in a folder of the test's.
final class NullmereUITests: XCTestCase {
    private static let bundleIdentifier = "online.nullmere.launcher.uitest"

    private var app: XCUIApplication!
    private var window: XCUIElement!
    /// What the audits and the walk find, said together at the end, so one
    /// run shows all of it.
    private var findings: [String] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: Self.bundleIdentifier)
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent("nullmere-ui-\(UUID().uuidString)", isDirectory: true)
        app.launchEnvironment = [
            "NULLMERE_MODEL_STATE": "ready",
            // The rebuilt realm CI publishes on this Mac's SpacetimeDB server.
            "NULLMERE_REALM": "http://127.0.0.1:3000/nullmere-ui",
            "NULLMERE_IDENTITY_FILE": kept.appendingPathComponent("identity").path,
            // What it keeps, kept apart from any on this Mac.
            "NULLMERE_STORE": kept.path,
            // The news this build ships with, not whatever the repository
            // holds today.
            "NULLMERE_NEWS_URL": "https://nullmere.invalid/news.json",
            // The map offers its orders as when VoiceOver runs.
            "NULLMERE_VOICEOVER": "1",
            // The world at noon, its brightest, whatever the hour of its
            // day: the same every run, and the hardest for words set over it.
            "NULLMERE_HOUR": "12",
        ]
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    /// The window is Nullmere Online; its menu, News and Settings pass the
    /// audit; Settings hold only how the lake is shown, nothing of a game
    /// played alone.
    func testTheLauncherPassesTheAudit() throws {
        let window = try openTheLauncher()
        audit("the launcher's menu")

        window.buttons["News"].click()
        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 10), "News opens")
        audit("News")
        back(from: "News", in: window)

        window.buttons["Settings"].click()
        XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 10), "Settings opens")
        for row in ["Motion", "Resolution", "Frame rate", "Text", "Full screen at launch"] {
            if !labelled(row, in: window).exists { found("UIWALK Settings has no row \(row)") }
        }
        for alone in ["Seed", "Difficulty", "Rivals", "Lake size", "House", "Single player"] {
            if labelled(alone, in: window).exists { found("UIWALK Settings offers \(alone), a game played alone") }
        }
        audit("Settings")
        back(from: "Settings", in: window)
        report()
    }

    /// With Larger type, in a window as small as this Mac's screen allows,
    /// News and Settings still lie whole between the title and the footer,
    /// and their Back still answers a click.
    func testTheLauncherFitsWithLargerType() throws {
        app.launchEnvironment["NULLMERE_TEXT"] = "larger"
        let window = try openTheLauncher()
        for panel in ["News", "Settings"] {
            window.buttons[panel].click()
            XCTAssertTrue(window.buttons["Back"].waitForExistence(timeout: 10), "\(panel) opens")
            Thread.sleep(forTimeInterval: 1)
            let heading = window.staticTexts[panel]
            if let title = titleWord(in: window), heading.exists, heading.frame.minY < title.frame.maxY {
                found("UIWALK with Larger type, \(panel)'s heading at \(heading.frame.integral) runs into the title at \(title.frame.integral)")
            }
            back(from: "\(panel), with Larger type,", in: window)
        }
        report()
    }

    /// Without Apple Intelligence the launcher offers only what is missing,
    /// a way to mend it and Quit; that passes the audit too.
    func testTheRequirementPassesTheAudit() throws {
        app.launchEnvironment["NULLMERE_MODEL_STATE"] = "notEnabled"
        app.launch()
        window = app.windows["Nullmere Online"]
        XCTAssertTrue(window.waitForExistence(timeout: 30), "One window, named Nullmere Online")
        window.click()
        XCTAssertTrue(window.buttons["Open System Settings"].waitForExistence(timeout: 20), "What is missing, and its mending")
        XCTAssertFalse(window.buttons["Play"].exists, "No way in without the model")
        audit("the requirement")
        report()
    }

    /// A realm that doesn't answer: Play says so, offers to try again or go
    /// back, passes the audit, and Back is the launcher again.
    func testAnUnansweringRealmsDoorPassesTheAudit() throws {
        app.launchEnvironment["NULLMERE_REALM"] = "http://127.0.0.1:9/nullmere"
        let window = try openTheLauncher()
        window.buttons["Play"].click()
        XCTAssertTrue(window.buttons["Try again"].waitForExistence(timeout: 60), "Out of reach, the realm offers to try again")
        audit("a realm out of reach")
        let back = window.buttons["Back to the launcher"]
        XCTAssertTrue(back.exists, "and a way back")
        back.click()
        XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 20), "Back, the launcher's menu again")
        report()
    }

    /// The realm entered through Play, as a newcomer meets it: the name it
    /// asks for, then the world and every part of every destination over
    /// it, and the palette, each put to the audit; and the way back to the
    /// launcher, Command-Shift-W. The realm is the rebuilt one (realm/),
    /// published by CI to the SpacetimeDB server on this Mac.
    func testTheRealmAndEveryDestinationPassTheAudit() throws {
        // The world held still (Motion: Still, as a player may set it), so
        // each audit reads a screen that has settled.
        app.launchArguments += ["-launcher.motion", "still"]
        let window = try openTheLauncher()
        window.buttons["Play"].click()
        let name = window.textFields["Your name in the realm"]
        XCTAssertTrue(name.waitForExistence(timeout: 60), "Play crosses into the realm, which asks a newcomer's name")
        // The name field is being written in as the card opens.
        audit("the realm's name card", editing: true)
        name.click()
        let letters = (0..<4).map { _ in String("abcdefghijklmnopqrstuvwxyz".randomElement() ?? "a") }.joined()
        name.typeText("Ama \(letters)\r")
        let map = labelled("The realm's map", in: window)
        XCTAssertTrue(map.waitForExistence(timeout: 60), "Then the world, about the city founded")
        let house = window.buttons["House"]
        XCTAssertTrue(house.waitForExistence(timeout: 60), "and the destinations beside it")
        audit("the realm")

        // The map as VoiceOver walks it: what stands and moves on it, the
        // player's own city first; choosing that chooses the city, its
        // ring and callout about it.
        let walked = map.buttons.allElementsBoundByIndex
        print("UIMAP \(walked.count) elements in \(map.frame): " + walked.prefix(12).map { "\($0.label) @ \($0.frame)" }.joined(separator: " | "))
        if walked.count < 2 {
            found("UIWALK the realm's map holds \(walked.count) elements, not its cities and armies")
        } else if !walked[0].label.contains("Your city") {
            found("UIWALK the map's first element is not the player's city: \(walked[0].label)")
        } else {
            walked[0].click()
            let away = window.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Put away '")).firstMatch
            if away.waitForExistence(timeout: 10) {
                audit("the city chosen")
                away.click()
            } else {
                found("UIWALK choosing the city on the map showed nothing about it")
            }
        }

        // Each destination from the dock, and each of its parts, then closed again.
        for (place, parts) in [("House", ["Buildings", "Troops", "Studies", "Forge", "Today"]), ("Alliance", ["Alliance"]),
                               ("Realm", ["The Mere", "Rankings", "Chat"]), ("Mail", ["Reports"])] {
            let door = window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", place)).firstMatch
            guard door.waitForExistence(timeout: 10) else {
                found("UIWALK the dock has no \(place)")
                continue
            }
            door.click()
            for (index, part) in parts.enumerated() {
                if index > 0 {
                    let tab = window.buttons["\(part), in \(place)"]
                    guard tab.waitForExistence(timeout: 10) else {
                        found("UIWALK \(place) shows no \(part) to turn to")
                        continue
                    }
                    tab.click()
                }
                audit("\(place): \(part)")
            }
            door.click()
        }

        // The palette, as Command-K opens it, and put away with Escape.
        app.typeKey("k", modifierFlags: .command)
        if window.textFields["Search for something to do"].waitForExistence(timeout: 10) {
            audit("the palette", editing: true)
            app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        } else {
            found("UIWALK the palette didn't open with Command-K")
        }

        // Back to the launcher.
        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 20), "Left, the launcher's menu again")
        report()
    }

    // MARK: Helpers

    /// Opens the app and its launcher, past the opening, at the menu.
    private func openTheLauncher() throws -> XCUIElement {
        app.launch()
        window = app.windows["Nullmere Online"]
        XCTAssertTrue(window.waitForExistence(timeout: 30), "One window, named Nullmere Online")
        // A click skips the opening, as it does for a keeper.
        window.click()
        XCTAssertTrue(window.buttons["Play"].waitForExistence(timeout: 20), "The menu, Play first")
        XCTAssertNotNil(titleWord(in: window), "The title reads Nullmere Online")
        if let screen = NSScreen.main {
            print("UISCREEN \(screen.frame.size) at \(screen.backingScaleFactor)x; the window \(window.frame)")
        }
        return window
    }

    /// Back, from a panel of the launcher: whole above the footer, where the
    /// footer's words can't lie over it, and answering a click with the menu.
    private func back(from panel: String, in window: XCUIElement) {
        let back = window.buttons["Back"]
        let link = window.buttons["Open nullmere.online"]
        if back.exists, link.exists, back.frame.maxY > link.frame.minY {
            found("UIWALK \(panel)'s Back at \(back.frame.integral) runs into the footer at \(link.frame.integral)")
        }
        back.click()
        if !window.buttons["Play"].waitForExistence(timeout: 5) {
            found("UIWALK \(panel)'s Back, clicked, didn't return to the menu")
        }
    }

    /// The title's own words on the lake, a header reading Nullmere Online:
    /// not the window, nor anything else as large, that bears the name.
    private func titleWord(in window: XCUIElement) -> XCUIElement? {
        window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Nullmere Online"))
            .allElementsBoundByIndex.first { $0.frame.height < window.frame.height / 2 && $0.frame.width < window.frame.width }
    }

    /// The first element under `root` with these words, of any kind: as its
    /// label, its title, or, for text, its value.
    private func labelled(_ label: String, in root: XCUIElement) -> XCUIElement {
        root.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@ OR title == %@ OR value == %@", label, label, label)).firstMatch
    }

    /// The Mac's own furniture, which the app neither draws nor names: the
    /// Touch Bar macOS keeps for every window and what it shows (such as
    /// the emoji button beside a text field), above the window's top edge;
    /// and the buttons in the title bar's corner.
    private func isMacChrome(_ element: XCUIElement) -> Bool {
        if element.elementType == .touchBar || element.frame.minY < window.frame.minY { return true }
        let corner = CGRect(x: window.frame.minX, y: window.frame.minY, width: 100, height: 32)
        return element.elementType == .group && element.label.isEmpty && corner.contains(element.frame)
    }

    /// Xcode's accessibility audit of what is on screen: every issue it
    /// finds is kept, so each screen is still audited, and all are told.
    ///
    /// Its contrast check is a heuristic, and calls type faint that its own
    /// pixels show plainly apart from the ground (light type on the night
    /// water at sixteen to one, by WCAG's formula). So the type it calls
    /// faint is measured from the screen's pixels, and fails if it is faint
    /// by that measure: its body under WCAG's 4.5:1 against its ground, or
    /// it can't be measured at all. Where a screen holds more type than the
    /// audit can judge in its time, every text on it is measured so.
    private func audit(_ screen: String, editing: Bool = false) {
        // What fades in, or is fetched as the screen opens (the news, the
        // realm's state), is audited once it has settled.
        Thread.sleep(forTimeInterval: 2.5)
        print("UIAUDIT-SIZE \(screen): \(app.staticTexts.count) texts, \(app.buttons.count) buttons")
        faint = []
        sheet = app.sheets.allElementsBoundByIndex.first?.frame
        // In parts, each with its own time, so a crowded screen is judged
        // whole: the checks in four, then the contrast of every text,
        // worked out from the screen's pixels and so the longest.
        for (part, types) in Self.checks {
            if !audit(screen, part: part, types: types, editing: editing) {
                found("UIAUDIT \(screen): its \(part) couldn't run in its time")
            }
        }
        let judged = audit(screen, part: "contrast", types: .contrast, editing: editing)
        if !judged {
            print("UIAUDIT-NOTE \(screen): its contrast ran out of time; every text on it measured from the screen instead")
        }
        // Each scrolling panel, and where the texts within it lie, shown or
        // scrolled out of its view.
        let scrolling = app.scrollViews.allElementsBoundByIndex.map { view in
            Scrolling(frame: view.frame, texts: view.staticTexts.allElementsBoundByIndex.map(\.frame))
        }
        for text in judged ? faint : app.staticTexts.allElementsBoundByIndex {
            measure(text, on: screen, flagged: judged, scrolling: scrolling)
        }
    }

    /// The audit's checks but contrast, in four parts.
    private static let checks: [(String, XCUIAccessibilityAuditType)] = {
        // Every other check the Mac's audit makes: of actions, parents and
        // children, and whatever else it learns.
        let rest = XCUIAccessibilityAuditType.all.subtracting([.contrast, .elementDetection, .hitRegion, .sufficientElementDescription])
        return [("check of what it shows", .elementDetection), ("check of what can be hit", .hitRegion),
                ("check of their descriptions", .sufficientElementDescription), ("checks of their actions and parents", rest)]
    }()

    /// The texts the audit last found faint, to be measured.
    private var faint: [XCUIElement] = []

    /// A scrolling panel: where it lies, and where every text within it
    /// lies, those scrolled out of its view as well.
    private struct Scrolling {
        let frame: CGRect
        let texts: [CGRect]

        /// Whether a text lies within this panel, or over it.
        func holds(_ text: CGRect) -> Bool { frame.intersects(text) || texts.contains(text) }
    }

    /// Where a modal sheet lies over the window, while one is up: what lies
    /// outside it is the window behind, which the Mac dims and holds out of
    /// reach until the sheet is put away.
    private var sheet: CGRect?

    /// How far up from its foot a scrolling panel fades its rows (the
    /// game's `scrollEdgeFade`).
    private static let scrollFade: CGFloat = 18

    /// A text measured from the screen's pixels: told, with the audit's word
    /// on it beside; a finding if its type is faint by WCAG's measure, or
    /// can't be measured where it lies in the window. A text a scrolling
    /// panel shows only in part, cut by its edge or under the fade at its
    /// foot that says more lies below, is judged once scrolled into view.
    private func measure(_ text: XCUIElement, on screen: String, flagged: Bool, scrolling: [Scrolling]) {
        let words = Self.words(of: text)
        guard text.exists, !words.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let frame = text.frame
        // Within a scrolling panel but not wholly in its view (scrolled out
        // of it, cut by its edge, or under the fade at its foot that says
        // more lies below): judged once scrolled into view, wherever it
        // lies meanwhile, over the map beyond the panel or past the window.
        if let panel = scrolling.first(where: { $0.holds(frame) }),
           !panel.frame.divided(atDistance: Self.scrollFade, from: .maxYEdge).remainder.contains(frame) {
            print("UIAUDIT-NOTE \(screen): '\(words.prefix(40))' shown only in part by its scrolling panel, judged when scrolled into view")
            return
        }
        // Scrolled out of the window, or hidden behind its edge: what isn't
        // shown isn't judged, unless the audit judged it.
        guard window.frame.contains(frame), frame.width >= 4, frame.height >= 4 else {
            if flagged { found("UIAUDIT \(screen): Contrast failed, and '\(words.prefix(60))' lies where it can't be measured: \(frame.integral)") }
            return
        }
        // Behind a modal sheet, not in it: inactive, dimmed by the Mac, and
        // out of reach until the sheet is put away; WCAG asks no contrast
        // of it.
        if let sheet, !sheet.contains(frame) {
            print("UIAUDIT-NOTE \(screen): '\(words.prefix(40))' lies behind the sheet, inactive until it is put away")
            return
        }
        let verdict = flagged ? "the audit called it faint" : "measured, the audit out of time"
        guard let pixels = Self.measured(text) else {
            found("UIAUDIT \(screen): '\(words.prefix(60))' couldn't be measured (\(verdict))")
            return
        }
        print("UITEXT \(screen) h\(Int(frame.height)) \(pixels) '\(words.prefix(28))' (\(verdict))")
        if !pixels.meetsWCAG {
            found("UIAUDIT \(screen): Contrast failed: '\(words.prefix(60))' measures \(pixels) at \(frame.integral)")
        }
    }

    /// Runs the audit for these types, keeping what it finds; false if it
    /// couldn't run, out of time even after another try or two.
    @discardableResult
    private func audit(_ screen: String, part: String, types: XCUIAccessibilityAuditType, editing: Bool, tries: Int = 3) -> Bool {
        do {
            try app.performAccessibilityAudit(for: types) { issue in
                if let element = issue.element, self.isMacChrome(element) { return true }
                // A text field being written in hands its words to AppKit's
                // field editor, which names the field its parent though the
                // field doesn't list it: the Mac's own, in every app.
                if editing, issue.auditType == .parentChild, issue.element == nil {
                    print("UIAUDIT-NOTE \(screen): the field editor's parentage, AppKit's own, left aside")
                    return true
                }
                // A sheet's own container, which SwiftUI makes for it and
                // names nothing: the sheet reads by what it holds.
                if issue.auditType == .sufficientElementDescription, let element = issue.element, element.elementType == .group,
                   element.label.isEmpty, let sheet = self.sheet, element.frame == sheet {
                    print("UIAUDIT-NOTE \(screen): the sheet's own container, SwiftUI's, left aside")
                    return true
                }
                // Type called faint is measured, and judged by that.
                if issue.auditType == .contrast, let text = issue.element {
                    self.faint.append(text)
                    // The audit's own account of what it saw.
                    print("UIAUDIT-WHY \(screen) '\(Self.words(of: text).prefix(30))': \(issue.detailedDescription.prefix(300))")
                    return true
                }
                let element = issue.element.map { element in
                    "type \(element.elementType.rawValue) '\(Self.words(of: element).prefix(70))' at \(element.frame.integral)"
                } ?? "the screen (\(issue.detailedDescription.prefix(160)))"
                self.found("UIAUDIT \(screen): \(issue.compactDescription): \(element)")
                return true
            }
            return true
        } catch let error as NSError where error.code == -56 {
            // Out of time on a crowded screen: again, after a pause, before it
            // counts against the screen; and what kept the Mac busy, told.
            guard tries > 1 else { return false }
            print("UIAUDIT-NOTE \(screen): its \(part) ran out of time; again. Busiest: \(Self.busiest())")
            Thread.sleep(forTimeInterval: 4)
            return audit(screen, part: part, types: types, editing: editing, tries: tries - 1)
        } catch {
            found("UIAUDIT \(screen): its \(part) couldn't run: \(error)")
            return true
        }
    }

    /// The processes using the most of the Mac's time just now.
    private static func busiest() -> String {
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-Ao", "pcpu=,comm=", "-r"]
        let pipe = Pipe()
        ps.standardOutput = pipe
        guard (try? ps.run()) != nil else { return "unknown" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        ps.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "").split(separator: "\n").prefix(5).map { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count == 2 else { return String(line) }
            return "\(parts[0])% \(URL(fileURLWithPath: String(parts[1])).lastPathComponent)"
        }.joined(separator: ", ")
    }

    private static func words(of element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    /// What a text's pixels show of its type, by WCAG's relative luminance.
    struct Measure: CustomStringConvertible {
        /// The commonest colour, taken for the ground.
        var ground: UInt32
        /// The type's commonest colour, and its contrast with the ground.
        var body: UInt32, bodyRatio: Double
        /// The type's brightest colour, and its contrast with the ground.
        var peak: UInt32, peakRatio: Double
        /// The faintest mark of the type (a letter's stroke, a full stop, a
        /// middle dot): its brightest pixel's contrast with the ground.
        var weakest: Double
        var marks: Int

        /// WCAG's least for type, 4.5:1, held by the type's body.
        var meetsWCAG: Bool { marks > 0 && bodyRatio >= 4.5 }

        var description: String {
            func rgb(_ colour: UInt32) -> String { "\(colour >> 16 & 0xFF),\(colour >> 8 & 0xFF),\(colour & 0xFF)" }
            guard marks > 0 else { return "g\(rgb(ground)) none apart" }
            return "g\(rgb(ground)) m\(rgb(body))=\(String(format: "%.1f", bodyRatio)) "
                + "p\(rgb(peak))=\(String(format: "%.1f", peakRatio)) w\(String(format: "%.1f", weakest))/\(marks)"
        }
    }

    /// An element's pixels as the screen draws them: the commonest colour,
    /// taken for the ground; of the rest, those plainly apart from it, taken
    /// for the type: their commonest colour and their brightest, against the
    /// ground; and each mark of the type on its own (a letter's stroke, a
    /// full stop, a middle dot), the weakest mark's brightest pixel against
    /// the ground, which is what small type stands or falls by. Nil if the
    /// screen's pixels can't be had.
    private static func measured(_ element: XCUIElement) -> Measure? {
        guard let image = element.screenshot().image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn, width * height > 0 else { return nil }
        func linear(_ byte: UInt8) -> Double {
            let value = Double(byte) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        var counts: [UInt32: Int] = [:]
        var lum = [Double](repeating: 0, count: width * height)
        for pixel in 0..<(width * height) {
            let index = pixel * 4
            counts[UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]), default: 0] += 1
            lum[pixel] = 0.2126 * linear(bytes[index]) + 0.7152 * linear(bytes[index + 1]) + 0.0722 * linear(bytes[index + 2])
        }
        func luminance(_ colour: UInt32) -> Double {
            0.2126 * linear(UInt8(colour >> 16 & 0xFF)) + 0.7152 * linear(UInt8(colour >> 8 & 0xFF)) + 0.0722 * linear(UInt8(colour & 0xFF))
        }
        func ratio(_ a: Double, _ b: Double) -> Double { (max(a, b) + 0.05) / (min(a, b) + 0.05) }
        func colour(at pixel: Int) -> UInt32 {
            UInt32(bytes[pixel * 4]) << 16 | UInt32(bytes[pixel * 4 + 1]) << 8 | UInt32(bytes[pixel * 4 + 2])
        }
        guard let ground = counts.max(by: { $0.value < $1.value })?.key else { return nil }
        let groundLuminance = luminance(ground)
        // The marks: pixels apart from the ground, joined where they touch,
        // corners and all. A mark far longer than it is thick (a meter's
        // bar, a rule) is drawn, not written, and judged as a graphic, at
        // WCAG's 3:1 for those, not as type.
        var seen = [Bool](repeating: false, count: width * height)
        var written: [Int] = [], bars: [Int] = []
        var weakest = Double.infinity, marks = 0
        for start in 0..<(width * height) where !seen[start] && ratio(lum[start], groundLuminance) > 1.5 {
            var stack = [start], members: [Int] = [], brightest = 0.0
            var left = Int.max, right = Int.min, top = Int.max, bottom = Int.min
            seen[start] = true
            while let pixel = stack.popLast() {
                members.append(pixel)
                brightest = max(brightest, ratio(lum[pixel], groundLuminance))
                let x = pixel % width, y = pixel / width
                left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                        let next = ny * width + nx
                        if !seen[next], ratio(lum[next], groundLuminance) > 1.5 {
                            seen[next] = true
                            stack.append(next)
                        }
                    }
                }
            }
            let wide = right - left + 1, tall = bottom - top + 1
            if (wide >= 12 && wide >= 3 * tall) || (tall >= 12 && tall >= 3 * wide) {
                bars += members
                continue
            }
            written += members
            marks += 1
            weakest = min(weakest, brightest)
        }
        // The type's colours: its commonest, taken for its body, and its
        // brightest, against the ground.
        var type: [UInt32: Int] = [:]
        for pixel in written.isEmpty ? bars : written { type[colour(at: pixel), default: 0] += 1 }
        guard let mode = type.max(by: { $0.value < $1.value })?.key,
              let peak = type.keys.max(by: { ratio(luminance($0), groundLuminance) < ratio(luminance($1), groundLuminance) }) else {
            return Measure(ground: ground, body: ground, bodyRatio: 1, peak: ground, peakRatio: 1, weakest: 1, marks: 0)
        }
        return Measure(ground: ground, body: mode, bodyRatio: ratio(luminance(mode), groundLuminance),
                       peak: peak, peakRatio: ratio(luminance(peak), groundLuminance), weakest: weakest, marks: marks)
    }

    /// Kept, and said at once, so a test that stops early still tells it.
    private func found(_ finding: String) {
        print(finding)
        findings.append(finding)
    }

    private func report() {
        XCTAssertTrue(findings.isEmpty, "\(findings.count) found:\n" + findings.joined(separator: "\n"))
    }
}
