import XCTest
import ImageIO

/// Screenshot review uses production views and simulator-only synthetic models.
/// No test submits a connection, remote command, upload, deletion or clipboard write.
@MainActor
final class UIReviewScreenshots: XCTestCase {
    private var app: XCUIApplication!
    private var appearance: String { ProcessInfo.processInfo.environment["TRUNKLINE_CAPTURE_APPEARANCE"] ?? "light" }
    private var orientation: String { ProcessInfo.processInfo.environment["TRUNKLINE_CAPTURE_ORIENTATION"] ?? "portrait" }

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = orientation == "landscape" ? .landscapeLeft : .portrait
        app = XCUIApplication()
        app.launchArguments = ["--ui-review"]
        app.launchEnvironment["TRUNKLINE_REVIEW_APPEARANCE"] = appearance
        app.launchEnvironment["TRUNKLINE_REVIEW_MULTIPLE_DISPLAYS"] = "1"
    }

    override func tearDownWithError() throws { app.terminate() }

    private func launch(_ section: String, extra: [String: String] = [:]) {
        app.terminate()
        app.launchEnvironment["TRUNKLINE_REVIEW_SECTION"] = section
        for key in ["TRUNKLINE_REVIEW_EMPTY_TERMINALS", "TRUNKLINE_REVIEW_LOADING_TERMINALS", "TRUNKLINE_REVIEW_CREATING_TERMINAL", "TRUNKLINE_REVIEW_LEGACY_FILES", "TRUNKLINE_REVIEW_DELAY_REFRESH", "TRUNKLINE_REVIEW_LARGE_TEXT", "TRUNKLINE_REVIEW_TERMINAL_HISTORY"] {
            app.launchEnvironment[key] = extra[key] ?? "0"
        }
        app.launch()
        let ready = app.staticTexts["ui-review-ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 15), "Review view never replaced launch screen")
        let correctAppearance = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", appearance), object: ready)
        XCTAssertEqual(XCTWaiter.wait(for: [correctAppearance], timeout: 8), .completed, "Wrong effective appearance")
    }

    private func capture(_ name: String, ready: XCUIElement? = nil, readinessTimeout: TimeInterval = 8) {
        let isReady = ready?.waitForExistence(timeout: readinessTimeout) ?? true
        // App-element screenshots can report portrait geometry for a landscape iPad.
        // Capture the actual device display, including system sheets and popovers.
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(isReady ? "" : "FAILED-")\(name)-\(appearance)-\(orientation)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let source = CGImageSourceCreateWithData(screenshot.pngRepresentation as CFData, nil)!
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)! as NSDictionary
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let imageOrientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let rotated = (5...8).contains(imageOrientation)
        let landscape = rotated ? height > width : width > height
        let metadata = XCTAttachment(string: "appearance=\(appearance) orientation=\(orientation) pixels=\(width)x\(height) exif=\(imageOrientation)")
        metadata.name = "\(name)-capture-metadata"
        metadata.lifetime = .keepAlways
        add(metadata)
        if !isReady {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "\(name)-missing-screen-hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertTrue(isReady, "Missing screen: \(name)")
        XCTAssertEqual(landscape, orientation == "landscape", "Wrong displayed screenshot orientation: \(width)x\(height), EXIF \(imageOrientation)")
    }

    private func menuItem(_ title: String) -> XCUIElement {
        // SwiftUI menu actions may expose Button or PopUpButton across snapshots.
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func tapMenuItem(_ title: String) {
        revealMenuItem(title)
        let target = menuItem(title)
        XCTAssertTrue(target.exists && target.isHittable, "Menu action is not visible: \(title)")
        target.tap()
    }

    private func revealMenuItem(_ title: String) {
        let target = menuItem(title)
        // Native bottom-anchored menus reverse their visual order and create only
        // visible cells. Scroll the menu itself in both directions, boundedly.
        for down in [true, false] {
            for _ in 0..<4 {
                if target.exists && target.isHittable { return }
                guard app.collectionViews.count > 0 else {
                    XCTFail("No open menu contains \(title)"); return
                }
                let menu = app.collectionViews.element(boundBy: app.collectionViews.count - 1)
                let visible = menu.frame.intersection(app.frame)
                let x = visible.midX
                let startY = visible.minY + visible.height * (down ? 0.3 : 0.7)
                let endY = visible.minY + visible.height * (down ? 0.7 : 0.3)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                origin.withOffset(CGVector(dx: x, dy: startY)).press(forDuration: 0.05,
                    thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY)))
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Could not reveal menu item: \(title)")
    }

    func testTerminalStartedInLandscapeFillsPortrait() {
        XCUIDevice.shared.orientation = .landscapeLeft
        launch("terminal")
        let session = app.staticTexts["Project · build"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 8))
        session.tap()
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = direction
            let terminal = app.textViews["Mac terminal session"]
            let history = app.buttons["Up arrow"].firstMatch
            XCTAssertTrue(terminal.waitForExistence(timeout: 8))
            XCTAssertTrue(history.exists)
            XCTAssertGreaterThanOrEqual(terminal.frame.width, app.frame.width * 0.85)
            XCTAssertEqual(terminal.frame.maxY, history.frame.minY, accuracy: 24,
                           "Terminal must reach the shortcut bar after rotation")
            XCTAssertGreaterThan(terminal.frame.height, app.frame.height * 0.55)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "landscape-start-terminal-\(direction.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testConnectedTerminalRotation() {
        launch("terminal")
        let session = app.staticTexts["Project · build"].firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 8))
        session.tap()
        XCTAssertTrue(app.buttons["Session controls"].waitForExistence(timeout: 8))
        let resting = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        resting.name = "connected-terminal-no-keyboard"
        resting.lifetime = .keepAlways
        add(resting)
        // The terminal shortcut row must not sit underneath the floating tab bar.
        let tabs = app.tabBars.firstMatch
        let history = app.buttons["Up arrow"].firstMatch
        if tabs.exists {
            XCTAssertFalse(history.frame.intersects(tabs.frame), "Terminal shortcuts overlap workspace navigation")
        }
        XCTAssertFalse(tabs.exists, "An open terminal should use the full workspace without a second navigation bar")
        tap("Show keyboard")
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft, .portrait, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = direction
            XCTAssertTrue(app.buttons["terminal.key.Hide keyboard"].waitForExistence(timeout: 8))
            let terminal = app.textViews["Mac terminal session"]
            let escape = app.buttons["terminal.key.Up arrow"]
            XCTAssertTrue(terminal.exists)
            XCTAssertGreaterThanOrEqual(terminal.frame.width, app.frame.width * 0.85,
                                        "Sidebar crowds the terminal beside a full-width keyboard")
            XCTAssertLessThanOrEqual(terminal.frame.maxY, escape.frame.minY + 1,
                                     "Keyboard accessory covers the terminal")
            XCTAssertGreaterThan(terminal.frame.height, 70, "Terminal collapsed above the keyboard")
            XCTAssertEqual(terminal.frame.maxY, escape.frame.minY, accuracy: 8,
                           "Terminal leaves an unused gap above the accessory")
            let systemKey = app.keys["q"].firstMatch
            XCTAssertTrue(systemKey.waitForExistence(timeout: 8))
            XCTAssertLessThanOrEqual(escape.frame.maxY, systemKey.frame.minY,
                                     "Shortcut keys fell underneath the software keyboard")
            XCTAssertTrue(escape.isHittable)
            XCTAssertTrue(app.buttons["Session controls"].isHittable)
            XCTAssertTrue(app.frame.contains(app.buttons["Session controls"].frame),
                          "Session navigation moved outside the rotated window")
            XCTAssertTrue(app.frame.contains(escape.frame),
                          "Shortcut navigation moved outside the rotated window")
            XCTAssertGreaterThanOrEqual(terminal.frame.minY,
                                        app.buttons["Session controls"].frame.maxY - 1,
                                        "Session navigation covers terminal content")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "connected-terminal-\(direction.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "connected-terminal-hierarchy-\(direction.rawValue)"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        app.buttons["terminal.key.Hide keyboard"].tap()
        app.navigationBars.buttons["BackButton"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Project · build"].firstMatch.waitForExistence(timeout: 8))
        // Popping the detail must restore workspace navigation, not leave its
        // hidden-tab preference attached to the session list.
        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertTrue(app.tabBars.buttons["Controls"].waitForExistence(timeout: 5))
            app.tabBars.buttons["Controls"].tap()
            XCTAssertTrue(app.buttons["Spotlight"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    func testTerminalTouchFocusAndKeyboardDismissalAcrossRotation() {
        launch("terminal")
        app.staticTexts["Project · build"].firstMatch.tap()
        let terminal = app.textViews["Mac terminal session"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 8))
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = direction
            terminal.tap()
            let dismiss = app.buttons["terminal.key.Hide keyboard"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 8), "Touching the terminal must open the keyboard")
            let escape = app.buttons["terminal.key.Up arrow"]
            let key = app.keys["q"].firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 8))
            XCTAssertLessThanOrEqual(escape.frame.maxY, key.frame.minY)
            XCTAssertEqual(terminal.frame.maxY, escape.frame.minY, accuracy: 8)
            XCTAssertTrue(escape.isHittable)
            escape.tap()
            app.typeText("test")
            dismiss.tap()
            XCTAssertTrue(app.buttons["Show keyboard"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["Up arrow"].firstMatch.isHittable)
            XCTAssertGreaterThan(terminal.frame.height, app.frame.height * 0.55)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "terminal-touch-dismiss-\(direction.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testTerminalScrollDismissAndRotationWithHistory() {
        launch("terminal", extra: ["TRUNKLINE_REVIEW_TERMINAL_HISTORY": "1"])
        app.staticTexts["Project · build"].firstMatch.tap()
        let terminal = app.textViews["Mac terminal session"]
        XCTAssertTrue(terminal.waitForExistence(timeout: 8))
        terminal.tap()
        XCTAssertTrue(app.buttons["terminal.key.Hide keyboard"].waitForExistence(timeout: 8))
        // Real sessions have scrollback. Exercise interactive keyboard dismissal,
        // which can change focus while the rotation transition is also running.
        let top = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        let bottom = terminal.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95))
        top.press(forDuration: 0.05, thenDragTo: bottom)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Show keyboard' OR label == 'Hide keyboard'")).firstMatch.tap()
        if !app.buttons["terminal.key.Hide keyboard"].exists { terminal.tap() }
        for direction: UIDeviceOrientation in [.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = direction
            let escape = app.buttons["terminal.key.Up arrow"]
            XCTAssertTrue(escape.waitForExistence(timeout: 8))
            XCTAssertTrue(escape.isHittable)
            let key = app.keys["q"].firstMatch
            XCTAssertTrue(key.exists)
            XCTAssertLessThanOrEqual(escape.frame.maxY, key.frame.minY)
            XCTAssertEqual(terminal.frame.maxY, escape.frame.minY, accuracy: 8)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "terminal-history-keyboard-\(direction.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
        }
    }

    func testTerminalMenuControlsStayVisible() {
        launch("terminal")
        app.staticTexts["Project · build"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Session controls"].waitForExistence(timeout: 8))
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = direction
            for label in ["Up arrow", "Down arrow", "Enter"] {
                let key = app.buttons[label].firstMatch
                XCTAssertTrue(key.isHittable, "\(label) must be visible before opening the keyboard")
                XCTAssertTrue(app.frame.contains(key.frame))
                key.tap()
            }
            tap("Show keyboard")
            for label in ["Up arrow", "Down arrow", "Enter"] {
                let key = app.buttons["terminal.key.\(label)"]
                XCTAssertTrue(key.waitForExistence(timeout: 8))
                XCTAssertTrue(key.isHittable, "\(label) must be visible without scrolling the accessory")
                XCTAssertTrue(app.frame.contains(key.frame))
                key.tap()
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "terminal-menu-controls-\(direction.rawValue)"
            shot.lifetime = .keepAlways
            add(shot)
            app.buttons["terminal.key.Hide keyboard"].tap()
        }
    }

    func testPasscodeKeyboardRotation() {
        launch("connection-saved")
        let secureField = app.secureTextFields["connection-passcode"]
        XCTAssertTrue(secureField.waitForExistence(timeout: 8))
        secureField.tap()
        secureField.typeText("layout-test")
        // Secure fields and their keyboard are redacted in screenshots. Reveal only
        // this synthetic draft to review the actual keyboard geometry.
        app.buttons["connection-passcode-visibility"].tap()
        let field = app.textFields["connection-passcode"]
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = direction
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
            let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                let keyboard = self.app.keyboards.firstMatch.frame
                return keyboard.intersection(self.app.frame).height > 100 &&
                    field.isHittable && field.frame.minY >= 0 && field.frame.maxY <= keyboard.minY
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                           "Passcode input is obscured after rotating with the keyboard open")
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "passcode-keyboard-\(direction.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(field.value as? String, "layout-test")
        XCTAssertTrue(field.isHittable)
        app.buttons["connection-passcode-visibility"].tap()
        XCTAssertTrue(secureField.exists)
        XCTAssertFalse(app.buttons["Done"].exists, "The passcode keyboard must not add a floating Done button")
    }

    func testControlsRotation() {
        launch("controls")
        let names = ["Spotlight", "Mission Control", "Show desktop", "Switch app", "App windows", "Screenshot"]
        for direction: UIDeviceOrientation in [.portrait, .landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = direction
            let first = app.buttons["Spotlight"].firstMatch
            XCTAssertTrue(first.waitForExistence(timeout: 8))
            let reachable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: first)
            XCTAssertEqual(XCTWaiter.wait(for: [reachable], timeout: 5), .completed,
                           "Sidebar must not cover the controls after rotation")
            let frames = names.map { app.buttons[$0].firstMatch.frame }
            XCTAssertEqual(frames[0].minY, frames[1].minY, accuracy: 1,
                           "Standard text should fit at least two actions per row on these full-screen devices")
            for frame in frames {
                XCTAssertGreaterThanOrEqual(frame.height, 44)
                XCTAssertEqual(frame.width, frames[0].width, accuracy: 1)
                XCTAssertEqual(frame.height, frames[0].height, accuracy: 1)
                XCTAssertGreaterThanOrEqual(frame.minX, 0)
                XCTAssertLessThanOrEqual(frame.maxX, app.frame.maxX)
            }
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "controls-rotation-\(direction.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testButtonsWithLargerText() {
        for (section, title) in [("connection-saved", "Connect"), ("controls", "Mission Control"), ("desktop", "Open desktop")] {
            launch(section, extra: ["TRUNKLINE_REVIEW_LARGE_TEXT": "1"])
            let action = app.buttons[title].firstMatch
            XCTAssertTrue(action.waitForExistence(timeout: 8))
            if !action.isHittable { reveal(action) }
            XCTAssertTrue(action.isHittable)
            XCTAssertGreaterThanOrEqual(action.frame.minX, 0)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX)
            capture(section + "-larger-text", ready: action)
        }
    }

    func testWorkspaceSmoke() {
        for section in ["connection", "connection-saved", "desktop", "desktop-session", "controls", "terminal", "terminal-detail", "files"] {
            launch(section)
            capture("smoke-" + section)
        }
    }

    func testDesktopPrimaryAction() {
        launch("desktop")
        capture("desktop-primary-action", ready: app.buttons["Open desktop"])
    }

    private func tap(_ title: String) {
        let target = app.buttons[title].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing button: \(title)")
        if !target.isHittable { reveal(target) }
        target.tap()
    }

    private func reveal(_ target: XCUIElement) {
        for _ in 0..<8 {
            if target.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(target.isHittable, "Could not reveal \(target.label)")
    }

    func testRefreshKeepsVisibleRowsAndToolbarInPlace() {
        for section in ["controls", "files"] {
            launch(section, extra: ["TRUNKLINE_REVIEW_DELAY_REFRESH": "1"])
            let refresh = app.buttons["Refresh"].firstMatch
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 8), .completed)
            let row = app.buttons[section == "controls" ? "Spotlight" : "Open Documents"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            let originalRow = row.frame
            let originalButton = refresh.frame
            refresh.tap()
            let refreshing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Refreshing"), object: refresh)
            XCTAssertEqual(XCTWaiter.wait(for: [refreshing], timeout: 3), .completed)
            XCTAssertEqual(row.frame.minY, originalRow.minY, accuracy: 1)
            XCTAssertEqual(refresh.frame.width, originalButton.width, accuracy: 1)
            capture("\(section)-refreshing", ready: refresh)
            let finished = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: refresh)
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 8), .completed)
            XCTAssertEqual(row.frame.minY, originalRow.minY, accuracy: 1)
        }
    }

    func testConnectionLayoutRotation() {
        for section in ["connection", "connection-saved"] {
            launch(section)
            let action = app.buttons[section == "connection" ? "Scan QR code" : "Connect"]
            for direction: UIDeviceOrientation in [.portrait, .landscapeLeft] {
                XCUIDevice.shared.orientation = direction
                XCTAssertTrue(action.waitForExistence(timeout: 5))
                if !action.isHittable { reveal(action) }
                let visible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    action.isHittable && self.app.frame.contains(action.frame)
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [visible], timeout: 5), .completed,
                               "Primary connection action is outside the visible screen: \(action.frame), app: \(app.frame)")
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "\(section)-rotation-\(direction.rawValue)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        }
    }

    func testConnectionSettingsAndMacSelection() {
        launch("connection-saved")
        XCTAssertFalse(app.buttons["Help and Mac setup"].exists)
        tap("Settings")
        capture("connection-settings", ready: app.navigationBars["Settings"])
        tap("Help and Mac setup")
        XCTAssertTrue(app.navigationBars["Help and privacy"].waitForExistence(timeout: 5))
        app.navigationBars["Help and privacy"].buttons["Done"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        app.navigationBars["Settings"].buttons["Done"].tap()
        tap("Connection options")
        tap("MacBook Pro")
        XCTAssertEqual(app.buttons["Connection options"].value as? String, "MacBook Pro")
        capture("connection-selected-mac", ready: app.buttons["Connect"])
    }

    func testConnectionScreens() {
        launch("connection")
        capture("connection", ready: app.navigationBars["Trunkline"])
        tap("Pairing link")
        capture("connection-manual", ready: app.textFields["trunkline://…"])
        launch("connection-saved")
        capture("connection-saved", ready: app.buttons["Connect"])
        tap("Connection options")
        capture("connection-options", ready: app.buttons["Forget Mac"])
        tap("Forget Mac")
        capture("connection-forget-confirmation", ready: app.buttons["Forget"])
        launch("connection-connecting")
        capture("connection-connecting", ready: app.staticTexts["Connecting to Studio Mac…"])
        launch("scanner")
        capture("scanner-unavailable", ready: app.staticTexts["Scanning isn’t supported on this device. Close this screen and paste the Mac’s pairing link instead."])
        launch("help")
        capture("help")
        app.swipeUp()
        capture("help-lower")
    }

    func testDesktopScreens() {
        launch("desktop")
        capture("desktop", ready: app.navigationBars["Desktop"])
        tap("Choose Mac display")
        capture("desktop-displays", ready: app.buttons["Refresh displays"])
        launch("desktop")
        tap("Macs")
        capture("desktop-mac-menu", ready: app.buttons["Add Mac"])
        tap("MacBook Pro")
        capture("desktop-switch-confirmation", ready: app.buttons["Disconnect and switch"])
        launch("desktop")
        tap("Macs")
        tap("Add Mac")
        capture("desktop-add-mac-confirmation", ready: app.buttons["Disconnect and add Mac"])
        launch("desktop")
        tap("Desktop options")
        capture("desktop-options", ready: app.buttons["Stream settings"])
        tap("Stream settings")
        capture("desktop-settings", ready: app.navigationBars["Stream settings"])
        tap("Done")
        tap("Desktop options")
        tap("Disconnect")
        capture("desktop-disconnect-confirmation", ready: app.staticTexts["Disconnect from your Mac?"])
    }

    func testDesktopViewerScreens() {
        launch("desktop-session")
        capture("desktop-viewer-placeholder", ready: app.buttons["Spaces and windows"])
        tap("Spaces and windows")
        capture("desktop-workspace-menu", ready: app.buttons["Gestures & displays"])
        tap("Gestures & displays")
        capture("desktop-gesture-help", ready: app.navigationBars["Desktop gestures"])
        app.swipeUp()
        capture("desktop-gesture-help-lower")
        tap("Done")
        if app.buttons["More desktop controls"].exists {
            tap("More desktop controls")
        } else {
            tap("Shortcuts")
        }
        revealMenuItem("Send text…")
        capture("desktop-shortcuts", ready: menuItem("Send text…"))
        tapMenuItem("Send text…")
        let editor = app.textViews["Text to send"]
        XCTAssertTrue(editor.waitForExistence(timeout: 8))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 8))
        let editorVisible = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            editor.isHittable && editor.frame.minY >= self.app.navigationBars["Send text"].frame.maxY &&
                editor.frame.maxY <= self.app.keyboards.firstMatch.frame.minY + 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [editorVisible], timeout: 5), .completed,
                       "Text editor must fit between navigation and keyboard")
        capture("desktop-send-text", ready: app.navigationBars["Send text"])
        tap("Cancel")
        if app.buttons["More desktop controls"].exists { tap("More desktop controls") }
        tapMenuItem("Mac controls")
        capture("desktop-controls-overlay", ready: app.navigationBars["Controls"])
        tap("Done")
        if app.buttons["More desktop controls"].exists { tap("More desktop controls") }
        tapMenuItem("Hide toolbar")
        capture("desktop-toolbar-hidden", ready: app.buttons["Controls"])
        launch("desktop")
        capture("desktop-primary-action", ready: app.buttons["Open desktop"])
    }

    func testTerminalScreens() {
        launch("terminal")
        capture("terminal-sessions", ready: app.navigationBars["Terminal"])
        tap("Start a terminal session")
        capture("terminal-new-session-menu")
        launch("terminal", extra: ["TRUNKLINE_REVIEW_EMPTY_TERMINALS": "1"])
        capture("terminal-empty")
        launch("terminal", extra: ["TRUNKLINE_REVIEW_LOADING_TERMINALS": "1"])
        capture("terminal-loading")
        launch("terminal", extra: ["TRUNKLINE_REVIEW_CREATING_TERMINAL": "1"])
        capture("terminal-creating")
        launch("terminal-detail")
        capture("terminal-detail", ready: app.buttons["Session controls"])
        tap("Show keyboard")
        capture("terminal-keyboard", ready: app.buttons["Hide keyboard"])
        let hideKeyboard = app.navigationBars.buttons["Hide keyboard"].firstMatch
        XCTAssertTrue(hideKeyboard.waitForExistence(timeout: 5))
        hideKeyboard.tap()
        tap("Session controls")
        capture("terminal-menu", ready: app.buttons["Paste text…"])
        tap("Paste text…")
        capture("terminal-paste", ready: app.navigationBars["Paste into session"])
        tap("Cancel")
        tap("Session controls")
        tap("Rename")
        capture("terminal-rename", ready: app.alerts["Rename session"])
        tap("Cancel")
        tap("Session controls")
        tap("End session")
        capture("terminal-end-confirmation", ready: app.staticTexts["End this terminal session?"])
        launch("terminal-ended")
        capture("terminal-ended", ready: app.staticTexts["Session ended"])
    }

    func testControlsScreens() {
        launch("controls")
        capture("controls", ready: app.navigationBars["Controls"])
        tap("Open app")
        capture("controls-app-launcher", ready: app.navigationBars["Open app"])
        launch("controls")
        tap("Actions for Safari")
        capture("controls-app-actions", ready: app.buttons["Quit"])
        tap("Quit")
        capture("controls-quit-confirmation", ready: app.alerts["Quit Safari?"])
        launch("controls")
        let clipboard = app.buttons["Clipboard"].firstMatch
        reveal(clipboard)
        // Clipboard becomes hittable while Power is still beneath the floating tab bar.
        app.swipeUp()
        capture("controls-lower", ready: clipboard)
        app.staticTexts["Power"].firstMatch.tap()
        capture("controls-power-menu", ready: app.buttons["Lock Mac"])
        tap("Lock Mac")
        capture("controls-power-confirmation", ready: app.alerts["Lock your Mac?"])
        launch("clipboard")
        capture("clipboard", ready: app.navigationBars["Clipboard"])
    }

    func testFilesScreens() {
        launch("files")
        capture("files", ready: app.navigationBars["Files"])
        tap("Actions for Design notes.pdf")
        capture("files-actions", ready: app.buttons["Rename"])
        tap("Rename")
        capture("files-rename", ready: app.alerts["Rename"])
        tap("Cancel")
        tap("Actions for Design notes.pdf")
        tap("Move to Trash")
        capture("files-trash-confirmation", ready: app.staticTexts["Move to Trash?"])
        launch("files")
        tap("Add file or folder")
        capture("files-add-menu", ready: app.buttons["New folder"])
        tap("New folder")
        capture("files-new-folder", ready: app.alerts["New folder"])
        tap("Cancel")
        tap("Sort files")
        capture("files-sort-menu", ready: app.buttons["Size (largest first)"])
        launch("files")
        tap("Open Documents")
        capture("files-folder", ready: app.buttons["Parent folder"])
        tap("Add file or folder")
        tap("Upload")
        // iPad evidence showed the system picker shell before its provider loaded.
        // Wait for its real Cancel control; a blank popover is not a captured picker.
        capture("files-upload-picker", ready: app.buttons["Cancel"], readinessTimeout: 30)
        launch("files-transfer")
        capture("files-transfer", ready: app.staticTexts["42% · Keep Trunkline open"])
        launch("files-downloaded")
        capture("files-downloaded", ready: app.buttons["Save or share Review notes.txt"])
        tap("Save or share Review notes.txt")
        capture("files-share-sheet")
        launch("files-empty")
        capture("files-empty", ready: app.staticTexts["No files here"])
        launch("files", extra: ["TRUNKLINE_REVIEW_LEGACY_FILES": "1"])
        capture("files-legacy")
    }
}
