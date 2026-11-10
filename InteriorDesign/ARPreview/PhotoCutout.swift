import UIKit
import Vision
import CoreImage

/// Lifts the piece of furniture out of its photo, leaving the background
/// see-through, using the iPhone's built-in subject lifting (the same as
/// touching and holding a photo in Photos). On the phone, free.
enum PhotoCutout {
    /// The cut-out piece, cropped tight around it, or nil if no clear
    /// subject was found (or in the Simulator, which can't run it).
    static func cutout(from image: UIImage) async -> CGImage? {
        guard let source = upright(image) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> CGImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: source, options: [:])
            do {
                try handler.perform([request])
                guard let result = request.results?.first, !result.allInstances.isEmpty else { return nil }
                let buffer = try result.generateMaskedImage(ofInstances: result.allInstances, from: handler, croppedToInstancesExtent: true)
                let ciImage = CIImage(cvPixelBuffer: buffer)
                let cut = CIContext().createCGImage(ciImage, from: ciImage.extent)
                // A sliver isn't a useful picture of the piece.
                guard let cut, cut.width > 24, cut.height > 24 else { return nil }
                return cut
            } catch {
                return nil
            }
        }.value
    }

    /// The photo drawn the right way up (camera photos often store a turn
    /// in their orientation instead), no bigger than 1024 pixels.
    static func upright(_ image: UIImage, maxSide: CGFloat = 1024) -> CGImage? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }.cgImage
    }

    /// How big to stand the photo up so it fits the piece's true size:
    /// as tall as the piece unless that would make it wider than the
    /// piece's widest side. In meters.
    static func standingSize(imageWidth: Int, imageHeight: Int, widthCm: Double, depthCm: Double, heightCm: Double) -> (width: Float, height: Float) {
        let aspect = Float(max(imageWidth, 1)) / Float(max(imageHeight, 1))
        let maxWidth = Float(max(widthCm, depthCm) / 100)
        var height = Float(max(heightCm, 1) / 100)
        var width = height * aspect
        if width > maxWidth {
            width = maxWidth
            height = width / aspect
        }
        return (width, height)
    }
}
