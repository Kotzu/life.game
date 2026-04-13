import ReplayKit
import CoreImage
import UIKit

/// Captureaza ecranul iPhone via ReplayKit.
/// - Nu necesita Developer Mode
/// - Nu necesita jailbreak
/// - Afiseaza bara rosie de inregistrare in status bar (norma iOS)
/// - Functioneaza in background cat timp app-ul are permisiune audio/processing
class ScreenCapture: NSObject, ObservableObject {
    static let shared = ScreenCapture()

    private let recorder   = RPScreenRecorder.shared()
    private let ciContext  = CIContext(options: [.useSoftwareRenderer: false])

    @Published var isCapturing = false

    /// Callback cu JPEG comprimat (gata de trimis la Claude API)
    var onFrame: ((Data) -> Void)?

    private var frameCounter  = 0
    private var frameInterval = 15   // din 30fps → ~2 frame-uri/sec

    // ── Public API ──────────────────────────────────────────────────────────

    func start(fps: Int = 2) async throws {
        frameInterval = max(1, 30 / fps)

        try await recorder.startCapture(
            handler: { [weak self] sampleBuffer, bufferType, error in
                guard bufferType == .video, error == nil else { return }
                self?.process(sampleBuffer: sampleBuffer)
            },
            completionHandler: nil
        )

        await MainActor.run { isCapturing = true }
    }

    func stop() {
        recorder.stopCapture { _ in }
        Task { @MainActor in isCapturing = false }
    }

    // ── Private ─────────────────────────────────────────────────────────────

    private func process(sampleBuffer: CMSampleBuffer) {
        frameCounter += 1
        guard frameCounter % frameInterval == 0 else { return }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let original = UIImage(cgImage: cgImage)
        let scaled   = original.scaledDown(toWidth: 768)

        guard let jpeg = scaled.jpegData(compressionQuality: 0.7) else { return }
        onFrame?(jpeg)
    }
}

extension UIImage {
    func scaledDown(toWidth maxWidth: CGFloat) -> UIImage {
        guard size.width > maxWidth else { return self }
        let scale  = maxWidth / size.width
        let newSz  = CGSize(width: maxWidth, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSz).image { _ in
            draw(in: CGRect(origin: .zero, size: newSz))
        }
    }
}
