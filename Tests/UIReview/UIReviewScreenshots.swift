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
        for key in ["TRUNKLINE_REVIEW_EMPTY_TERMINALS", "TRUNKLINE_REVIEW_LOADING_TERMINALS", "TRUNKLINE_REVIEW_CREATING_TERMINAL", "TRUNKLINE_REVIEW_LEGACY_FILES"] {
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
