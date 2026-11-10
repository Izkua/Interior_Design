import SwiftUI
import UIKit

/// A photo you can pinch to zoom and move with two fingers (one finger
/// too, in Tap mode), using the system's own zooming view. One finger
/// taps or paints, reported as points 0...1 across and down the photo.
struct ZoomableCanvas: UIViewRepresentable {
    let image: CGImage
    /// True in Paint and Erase: one finger draws instead of moving.
    let drawing: Bool
    var onTap: (CGPoint) -> Void
    /// The point, and whether this is the first point of a stroke.
    var onDraw: (CGPoint, Bool) -> Void
    var onZoom: (CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 8
        scroll.bouncesZoom = true
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView()
        imageView.isUserInteractionEnabled = true
        scroll.addSubview(imageView)
        context.coordinator.imageView = imageView

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        imageView.addGestureRecognizer(tap)
        let draw = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.drew(_:)))
        draw.maximumNumberOfTouches = 1
        imageView.addGestureRecognizer(draw)
        context.coordinator.draw = draw
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.imageView?.image?.cgImage !== image {
            coordinator.imageView?.image = UIImage(cgImage: image)
        }
        // Drawing: one finger paints, two move. Otherwise one finger moves.
        coordinator.draw?.isEnabled = drawing
        scroll.panGestureRecognizer.minimumNumberOfTouches = drawing ? 2 : 1
        coordinator.layout(in: scroll)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var parent: ZoomableCanvas
        weak var imageView: UIImageView?
        weak var draw: UIPanGestureRecognizer?
        private var laidOutSize: CGSize = .zero
        private var imageSize: CGSize = .zero

        init(_ parent: ZoomableCanvas) { self.parent = parent }

        /// Fits the photo in the view (at zoom 1) and keeps it centered.
        func layout(in scroll: UIScrollView) {
            guard let imageView, scroll.bounds.width > 0 else { return }
            let size = CGSize(width: parent.image.width, height: parent.image.height)
            guard scroll.bounds.size != laidOutSize || size != imageSize else { return }
            laidOutSize = scroll.bounds.size
            imageSize = size
            let scale = min(scroll.bounds.width / size.width, scroll.bounds.height / size.height)
            scroll.zoomScale = 1
            imageView.frame = CGRect(x: 0, y: 0, width: size.width * scale, height: size.height * scale)
            scroll.contentSize = imageView.frame.size
            center(scroll)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(scrollView)
            parent.onZoom(scrollView.zoomScale)
        }

        private func center(_ scroll: UIScrollView) {
            guard let imageView else { return }
            let dx = max((scroll.bounds.width - imageView.frame.width) / 2, 0)
            let dy = max((scroll.bounds.height - imageView.frame.height) / 2, 0)
            scroll.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        private func normalized(_ gesture: UIGestureRecognizer) -> CGPoint? {
            guard let view = imageView, view.bounds.width > 0 else { return nil }
            let p = gesture.location(in: view)
            return CGPoint(x: p.x / view.bounds.width, y: p.y / view.bounds.height)
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard !parent.drawing, let point = normalized(gesture) else { return }
            parent.onTap(point)
        }

        @objc func drew(_ gesture: UIPanGestureRecognizer) {
            guard let point = normalized(gesture) else { return }
            switch gesture.state {
            case .began: parent.onDraw(point, true)
            case .changed: parent.onDraw(point, false)
            default: break
            }
        }
    }
}
