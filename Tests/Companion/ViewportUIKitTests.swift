#if canImport(TrunklineCore)
import TrunklineCore
#endif
import XCTest
import UIKit
import AVFoundation
@testable import Trunkline

@MainActor final class ViewportUIKitTests: XCTestCase {
    func testRotationPreservesVideoFocalPointThroughNativeScrollResize() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let scroll = UIScrollView(frame: root.bounds)
        let content = UIView(frame: root.bounds)
        root.addSubview(scroll); scroll.addSubview(content)
        let viewport = ViewportCoordinator(scroll: scroll, content: content, aspect: 16.0 / 9)
        viewport.layout(in: root.bounds)
        scroll.setZoomScale(2, animated: false)
        // Video-space (0.6, 0.6) at the center of a 390×700 portrait viewport.
        scroll.contentOffset = CGPoint(x: 273, y: 393.875)
        root.frame.size = CGSize(width: 800, height: 350)
        root.layoutIfNeeded()
        viewport.layout(in: root.bounds)
        let center = content.convert(CGPoint(x: 400, y: 175), from: root)
        let video = ViewportGeometry.videoRect(in: content.bounds.size, aspect: 16.0 / 9)
        // UIKit rounds content offsets to backing pixels; use one physical pixel, not a subpixel fraction.
        XCTAssertEqual((center.x - video.minX) / video.width, 0.6, accuracy: 1 / (video.width * UIScreen.main.scale))
        XCTAssertEqual((center.y - video.minY) / video.height, 0.6, accuracy: 1 / (video.height * UIScreen.main.scale))
        // Keyboard/split-view resizing and returning to portrait must use the same focal point.
        for size in [CGSize(width: 800, height: 240), CGSize(width: 600, height: 500), CGSize(width: 390, height: 700)] {
            root.frame.size = size; root.layoutIfNeeded()
            viewport.layout(in: root.bounds)
            let center = content.convert(CGPoint(x: size.width / 2, y: size.height / 2), from: root)
            let video = ViewportGeometry.videoRect(in: content.bounds.size, aspect: 16.0 / 9)
            XCTAssertEqual((center.x - video.minX) / video.width, 0.6, accuracy: 1 / (video.width * UIScreen.main.scale))
            XCTAssertEqual((center.y - video.minY) / video.height, 0.6, accuracy: 1 / (video.height * UIScreen.main.scale))
        }
    }

    func testUIKitTouchConversionMatchesVisibleVideoAfterZoomAndPan() {
        for size in [CGSize(width: 390, height: 700), CGSize(width: 800, height: 350),
                     CGSize(width: 1024, height: 1240), CGSize(width: 1240, height: 900)] {
            let root = UIView(frame: CGRect(origin: .zero, size: size))
            let scroll = UIScrollView(frame: root.bounds)
            let content = UIView(frame: root.bounds)
            let videoLayer = AVSampleBufferDisplayLayer()
            content.layer.addSublayer(videoLayer)
            root.addSubview(scroll); scroll.addSubview(content)
            let viewport = ViewportCoordinator(scroll: scroll, content: content, aspect: 16.0 / 10)
            viewport.layout(in: root.bounds)
            scroll.setZoomScale(2, animated: false)
            scroll.contentOffset = CGPoint(x: size.width / 2, y: size.height / 2)
            let touch = content.convert(CGPoint(x: size.width / 2, y: size.height / 2), from: root)
            let point = ViewportGeometry.videoPosition(touch, in: content.bounds.size, aspect: 16.0 / 10)
            XCTAssertEqual(point.x / videoLayer.bounds.width, 0.5, accuracy: 0.001)
            XCTAssertEqual(point.y / videoLayer.bounds.height, 0.5, accuracy: 0.001)
            for fraction in [CGPoint(x: 0.4, y: 0.6), CGPoint(x: 0.6, y: 0.4)] {
                // Start at a visible point on the actual rendered layer, then follow UIKit's
                // screen-to-content conversion and the production input mapping.
                let imagePoint = CGPoint(x: videoLayer.bounds.width * fraction.x, y: videoLayer.bounds.height * fraction.y)
                let screenPoint = videoLayer.convert(imagePoint, to: root.layer)
                XCTAssertTrue(root.bounds.contains(screenPoint))
                let localTouch = content.convert(screenPoint, from: root)
                let input = ViewportGeometry.videoPosition(localTouch, in: content.bounds.size, aspect: 16.0 / 10)
                XCTAssertEqual(input.x / videoLayer.bounds.width, fraction.x, accuracy: 0.001)
                XCTAssertEqual(input.y / videoLayer.bounds.height, fraction.y, accuracy: 0.001)
            }
            XCTAssertEqual(scroll.zoomScale, 2)
            XCTAssertTrue(scroll.panGestureRecognizer.isEnabled)
        }
    }

    func testReturningToFitResetsPanAndKeepsVideoInsideTheResizedViewport() {
        let root = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 350))
        let scroll = UIScrollView(frame: root.bounds)
        let content = UIView(frame: root.bounds)
        let video = AVSampleBufferDisplayLayer()
        content.layer.addSublayer(video)
        root.addSubview(scroll); scroll.addSubview(content)
        let viewport = ViewportCoordinator(scroll: scroll, content: content, aspect: 16.0 / 10)
        viewport.layout(in: root.bounds)
        scroll.setZoomScale(3, animated: false)
        scroll.contentOffset = CGPoint(x: 900, y: 400)
        UIView.setAnimationsEnabled(false)
        defer { UIView.setAnimationsEnabled(true) }
        viewport.changeZoom(0)
        root.frame.size = CGSize(width: 390, height: 700); root.layoutIfNeeded()
        viewport.layout(in: root.bounds)
        XCTAssertEqual(scroll.zoomScale, 1)
        XCTAssertEqual(scroll.contentOffset, .zero)
        XCTAssertFalse(scroll.panGestureRecognizer.isEnabled)
        XCTAssertEqual(video.frame.width, 390, accuracy: 0.001)
        XCTAssertEqual(video.frame.height, 243.75, accuracy: 0.001)
        XCTAssertEqual(video.frame.midY, 350, accuracy: 0.001)
    }
}
