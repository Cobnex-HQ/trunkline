import CoreGraphics
import Foundation

public enum ViewportGeometry {
    public static func videoRect(in size: CGSize, aspect: CGFloat) -> CGRect {
        guard size.width > 0, size.height > 0, aspect.isFinite, aspect > 0 else { return .zero }
        let width = min(size.width, size.height * aspect)
        let height = width / aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }
    /// Fit the captured monitor, including when its aspect changes inside an existing
    /// encoded stream. The encoded canvas may extend beyond the view; only its black
    /// letterbox margins are clipped. Input still uses the complete encoded canvas.
    public static func canvasRect(in size: CGSize, encodedAspect: CGFloat, displayAspect: CGFloat) -> CGRect {
        guard encodedAspect.isFinite, encodedAspect > 0 else { return .zero }
        let sourceAspect = displayAspect.isFinite && displayAspect > 0 ? displayAspect : encodedAspect
        let picture = videoRect(in: size, aspect: sourceAspect)
        let canvas: CGSize
        if sourceAspect > encodedAspect { canvas = CGSize(width: picture.width, height: picture.width / encodedAspect) }
        else { canvas = CGSize(width: picture.height * encodedAspect, height: picture.height) }
        return CGRect(x: (size.width-canvas.width)/2, y: (size.height-canvas.height)/2, width: canvas.width, height: canvas.height)
    }

    /// Input arrives in untransformed content coordinates from UIKit, including while zoomed.
    public static func videoPosition(_ point: CGPoint, in size: CGSize, aspect: CGFloat) -> CGPoint {
        let rect = videoRect(in: size, aspect: aspect)
        guard point.x.isFinite, point.y.isFinite else { return .zero }
        return CGPoint(x: min(max(point.x - rect.minX, 0), rect.width),
                       y: min(max(point.y - rect.minY, 0), rect.height))
    }
    /// Preserve the video-space focal point when the unscaled viewport changes.
    /// UIKit remains responsible for converting touches through the zoom transform.
    public static func resizedOffset(old: CGSize, new: CGSize, zoom: CGFloat, offset: CGPoint, aspect: CGFloat) -> CGPoint {
        guard old.width > 0, old.height > 0, new.width > 0, new.height > 0,
              zoom.isFinite, zoom > 1, aspect.isFinite, aspect > 0 else { return .zero }
        let before = videoRect(in: old, aspect: aspect), after = videoRect(in: new, aspect: aspect)
        let x = ((offset.x + old.width / 2) / zoom - before.minX) / before.width
        let y = ((offset.y + old.height / 2) / zoom - before.minY) / before.height
        let targetX: CGFloat = (after.minX + x * after.width) * zoom - new.width / 2
        let targetY: CGFloat = (after.minY + y * after.height) * zoom - new.height / 2
        let maximumX: CGFloat = new.width * (zoom - 1)
        let maximumY: CGFloat = new.height * (zoom - 1)
        return CGPoint(x: min(max(targetX, CGFloat.zero), maximumX),
                       y: min(max(targetY, CGFloat.zero), maximumY))
    }
}
