#if canImport(TrunklineCore)
import TrunklineCore
#endif
import UIKit
import AVFoundation

/// Owns the native viewport independently of connection/decoder lifetime.
@objc(TrunklineViewportCoordinator)
@MainActor final class ViewportCoordinator: NSObject, UIScrollViewDelegate {
    private let scroll: UIScrollView
    private let content: UIView
    private let aspect: CGFloat
    private var displayAspect: CGFloat
    private var previousViewport = CGSize.zero
    private var stableOffset = CGPoint.zero
    private var stableScale: CGFloat = 1
    private var updatingLayout = false
    @objc var workspaceAction: ((String) -> Void)?

    @objc(initWithScroll:content:aspect:)
    init(scroll: UIScrollView, content: UIView, aspect: CGFloat) {
        self.scroll = scroll; self.content = content; self.aspect = aspect; self.displayAspect = aspect
        super.init()
        scroll.delegate = self
        scroll.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scroll.minimumZoomScale = 1; scroll.maximumZoomScale = 4
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsVerticalScrollIndicator = false; scroll.showsHorizontalScrollIndicator = false
        scroll.bounces = false; scroll.bouncesZoom = false
        scroll.delaysContentTouches = false; scroll.canCancelContentTouches = true
        scroll.panGestureRecognizer.minimumNumberOfTouches = 2
        scroll.panGestureRecognizer.maximumNumberOfTouches = 2
        for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
            let swipe = UISwipeGestureRecognizer(target: self, action: #selector(handleWorkspaceSwipe(_:)))
            swipe.direction = direction; swipe.numberOfTouchesRequired = 3
            swipe.cancelsTouchesInView = true
            swipe.name = "Trunkline workspace swipe"
            scroll.addGestureRecognizer(swipe)
        }
        scroll.panGestureRecognizer.isEnabled = false
        content.autoresizingMask = []
        TrunklineViewport.setDisplayAspect(aspect, on: content)
    }

    @objc func handleWorkspaceSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard gesture.state == .ended, !UIAccessibility.isVoiceOverRunning else { return }
        let action: String
        switch gesture.direction {
        case .left: action = "nextSpace"
        case .right: action = "previousSpace"
        case .up: action = "missionControl"
        case .down: action = "appWindows"
        default: return
        }
        workspaceAction?(action)
    }

    @objc(layoutInBounds:)
    func layout(in bounds: CGRect) {
        rememberStableViewport()
        updatingLayout = true
        defer { updatingLayout = false; rememberStableViewport() }
        scroll.frame = bounds
        let viewport = scroll.bounds.size
        guard viewport.width > 0, viewport.height > 0 else { return }
        if viewport != previousViewport {
            let scale = stableScale
            let offset = ViewportGeometry.resizedOffset(old: previousViewport, new: viewport,
                                                        zoom: scale, offset: stableOffset, aspect: displayAspect)
            previousViewport = viewport
            scroll.setZoomScale(1, animated: false)
            content.transform = .identity
            content.frame = CGRect(origin: .zero, size: viewport)
            scroll.contentSize = viewport
            updateVideoLayer()
            scroll.setZoomScale(scale, animated: false)
            scroll.setContentOffset(offset, animated: false)
        } else { updateVideoLayer() }
    }

    @objc(setDisplayAspect:)
    func setDisplayAspect(_ value: CGFloat) {
        guard value.isFinite, value > 0, abs(value - displayAspect) > 0.00001 else { return }
        displayAspect = value
        TrunklineViewport.setDisplayAspect(value, on: content)
        // A new monitor starts fitted, rather than inheriting a crop from the old one.
        scroll.setZoomScale(1, animated: false)
        scroll.setContentOffset(.zero, animated: false)
        updateVideoLayer()
    }

    private func updateVideoLayer() {
        let rect = TrunklineViewport.canvasRect(in: content, encodedAspect: aspect)
        CATransaction.begin(); CATransaction.setDisableActions(true)
        for layer in content.layer.sublayers ?? [] where layer is AVSampleBufferDisplayLayer {
            layer.bounds = CGRect(origin: .zero, size: rect.size)
            layer.position = CGPoint(x: rect.midX, y: rect.midY)
        }
        CATransaction.commit()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { content }
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.panGestureRecognizer.isEnabled = scrollView.zoomScale > 1.001
        rememberStableViewport()
    }
    func scrollViewDidScroll(_ scrollView: UIScrollView) { rememberStableViewport() }

    private func rememberStableViewport() {
        // Autoresizing may clamp the offset before the controller's layout callback.
        // Ignore delegate callbacks from that intermediate, differently-sized viewport.
        guard !updatingLayout, previousViewport != .zero, scroll.bounds.size == previousViewport else { return }
        stableOffset = scroll.contentOffset
        stableScale = max(1, scroll.zoomScale)
    }

    @objc(changeZoom:)
    func changeZoom(_ factor: CGFloat) {
        let animate = !UIAccessibility.isReduceMotionEnabled
        if factor == 0 { scroll.setZoomScale(1, animated: animate); return }
        let scale = min(4, max(1, scroll.zoomScale * factor))
        let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
        let center = CGPoint(x: (scroll.contentOffset.x + scroll.bounds.width / 2) / scroll.zoomScale,
                             y: (scroll.contentOffset.y + scroll.bounds.height / 2) / scroll.zoomScale)
        scroll.zoom(to: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                               width: size.width, height: size.height), animated: animate)
    }
}
