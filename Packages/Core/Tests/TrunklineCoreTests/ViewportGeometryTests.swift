import CoreGraphics
import XCTest
@testable import TrunklineCore

final class ViewportGeometryTests: XCTestCase {
    func testPointerMapsToVideoInBothOrientationsAndTabletSizes() {
        for size in [CGSize(width: 393, height: 750), CGSize(width: 750, height: 300),
                     CGSize(width: 1024, height: 1240), CGSize(width: 1240, height: 900)] {
            let rect = ViewportGeometry.videoRect(in: size, aspect: 16.0 / 10)
            for fraction in [CGFloat(0), 0.25, 0.5, 0.9, 1] {
                let local = CGPoint(x: rect.minX + rect.width * fraction, y: rect.minY + rect.height * fraction)
                let position = ViewportGeometry.videoPosition(local, in: size, aspect: 16.0 / 10)
                XCTAssertEqual(position.x / rect.width, fraction, accuracy: 0.0001)
                XCTAssertEqual(position.y / rect.height, fraction, accuracy: 0.0001)
            }
            XCTAssertEqual(ViewportGeometry.videoPosition(CGPoint(x: -20, y: -20), in: size, aspect: 1.6), .zero)
            XCTAssertEqual(ViewportGeometry.videoPosition(CGPoint(x: size.width + 20, y: size.height + 20), in: size, aspect: 1.6), CGPoint(x: rect.width, y: rect.height))
        }
    }
    func testRotationKeepsCenterOfVideoAtSameNormalizedPosition() {
        let point = ViewportGeometry.resizedOffset(old: CGSize(width: 390, height: 700), new: CGSize(width: 800, height: 350), zoom: 2, offset: CGPoint(x: 195, y: 350), aspect: 16.0/9)
        XCTAssertEqual(point.x, 400, accuracy: 0.01)
        XCTAssertEqual(point.y, 175, accuracy: 0.01)
    }
    func testFitNeverLeavesStalePanOffsetAfterResize() {
        let point = ViewportGeometry.resizedOffset(old: CGSize(width: 390, height: 700), new: CGSize(width: 800, height: 350), zoom: 1, offset: CGPoint(x: 100, y: 200), aspect: 16.0/9)
        XCTAssertEqual(point, .zero)
    }
    func testRotatedViewportClampsPanToRealContent() {
        let point = ViewportGeometry.resizedOffset(old: CGSize(width: 800, height: 350), new: CGSize(width: 390, height: 700), zoom: 3, offset: CGPoint(x: 1600, y: 700), aspect: 16.0/9)
        XCTAssertTrue((0...780).contains(point.x))
        XCTAssertTrue((0...1400).contains(point.y))
    }
}

extension ViewportGeometryTests {
    func testChangingMonitorFitsItsActualRatioInsideTheEncodedCanvas() {
        // The stream remains 16:10, but the selected monitor changes to 16:9.
        let canvas = ViewportGeometry.canvasRect(in: CGSize(width: 800, height: 350), encodedAspect: 1.6, displayAspect: 16.0/9)
        XCTAssertEqual(canvas.width/canvas.height, 1.6, accuracy: 0.00001)
        XCTAssertEqual(canvas.width, 350*16.0/9, accuracy: 0.00001)
        XCTAssertEqual(canvas.midX, 400, accuracy: 0.00001)
        XCTAssertEqual(canvas.midY, 175, accuracy: 0.00001)
        // A portrait monitor on an iPad uses the available height without stretching.
        let portrait = ViewportGeometry.canvasRect(in: CGSize(width: 1024, height: 900), encodedAspect: 1.6, displayAspect: 9.0/16)
        XCTAssertEqual(portrait.height, 900, accuracy: 0.00001)
        XCTAssertEqual(portrait.width, 1440, accuracy: 0.00001)
        XCTAssertEqual(portrait.midX, 512, accuracy: 0.00001)
    }
}
