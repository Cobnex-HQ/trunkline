#if canImport(TrunklineCore)
import TrunklineCore
#endif
import UIKit
import ObjectiveC

@objc(TrunklineViewport)
final class TrunklineViewport: NSObject {
    private static var displayAspectKey: UInt8 = 0
    static func setDisplayAspect(_ aspect: CGFloat, on view: UIView) {
        objc_setAssociatedObject(view, &displayAspectKey, NSNumber(value: Double(aspect)), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    @objc(canvasRectInView:encodedAspect:)
    static func canvasRect(in view: UIView, encodedAspect: CGFloat) -> CGRect {
        let source = (objc_getAssociatedObject(view, &displayAspectKey) as? NSNumber)?.doubleValue ?? Double(encodedAspect)
        var rect = ViewportGeometry.canvasRect(in: view.bounds.size, encodedAspect: encodedAspect, displayAspect: CGFloat(source))
        rect.origin.x += view.bounds.origin.x; rect.origin.y += view.bounds.origin.y
        return rect
    }
    @objc(videoPosition:inSize:aspect:)
    static func videoPosition(_ point: CGPoint, in size: CGSize, aspect: CGFloat) -> CGPoint {
        ViewportGeometry.videoPosition(point, in: size, aspect: aspect)
    }
    @objc(videoRectInSize:aspect:)
    static func videoRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        ViewportGeometry.videoRect(in: size, aspect: aspect)
    }
    @objc(resizedOffsetFrom:to:zoom:offset:aspect:)
    static func resizedOffset(from old: CGSize, to new: CGSize, zoom: CGFloat, offset: CGPoint, aspect: CGFloat) -> CGPoint {
        ViewportGeometry.resizedOffset(old: old, new: new, zoom: zoom, offset: offset, aspect: aspect)
    }
}
