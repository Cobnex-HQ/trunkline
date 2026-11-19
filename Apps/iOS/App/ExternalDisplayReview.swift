#if DEBUG && targetEnvironment(simulator)
import SwiftUI
import AVFoundation

/// Exercises the real external scene and buffer path without a Mac connection.
struct ExternalDisplayReviewSurface: UIViewControllerRepresentable {
    @Binding var controller: UIViewController?
    func makeUIViewController(context: Context) -> UIViewController {
        let preview = ExternalDisplayReviewController()
        DispatchQueue.main.async { controller = preview }
        return preview
    }
    func updateUIViewController(_ controller: UIViewController, context: Context) {}
}

private final class ExternalDisplayReviewController: UIViewController {
    private var timer: Timer?
    private var sample: CMSampleBuffer?
    override func viewDidLoad() {
        super.viewDidLoad()
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1200, height: 800)).image { context in
            UIColor.darkGray.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 30, y: 30, width: 1140, height: 20))
            context.fill(CGRect(x: 30, y: 750, width: 1140, height: 20))
            ("Trunkline display preview\n1200 × 800 · exact aspect ratio" as NSString).draw(
                in: CGRect(x: 80, y: 320, width: 1040, height: 200),
                withAttributes: [.font: UIFont.systemFont(ofSize: 48), .foregroundColor: UIColor.white])
        }
        let preview = UIImageView(image: image)
        preview.contentMode = .scaleAspectFit
        preview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(preview)
        NSLayoutConstraint.activate([preview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: view.trailingAnchor), preview.topAnchor.constraint(equalTo: view.topAnchor),
            preview.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        var pixel: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 1200, 800, kCVPixelFormatType_32BGRA, nil, &pixel)
        if let pixel, let cgImage = image.cgImage {
            CVPixelBufferLockBaseAddress(pixel, [])
            let bitmap = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 1200, height: 800, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
            bitmap?.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1200, height: 800))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            var format: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel, formatDescriptionOut: &format)
            if let format {
                var time = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
                CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixel,
                    formatDescription: format, sampleTiming: &time, sampleBufferOut: &sample)
            }
        }
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let sample = self.sample else { return }
                _ = TrunklineExternalVideo.shared().submit(sample, from: self.view, isKeyframe: true)
            }
        }
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate(); timer = nil
    }
}
#endif
