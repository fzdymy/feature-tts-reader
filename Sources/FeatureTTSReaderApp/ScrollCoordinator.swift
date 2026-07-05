import SwiftUI

// MARK: - ScrollCoordinator (for programmatic scroll-to-offset)

class ScrollCoordinator: ObservableObject {
    weak var scrollView: UIScrollView?

    func scrollTo(offset: CGFloat, animated: Bool = true) {
        guard let sv = scrollView else { return }
        let clamped = min(max(offset, 0), sv.contentSize.height - sv.bounds.height)
        sv.setContentOffset(CGPoint(x: 0, y: clamped), animated: animated)
    }
}

// MARK: - ScrollViewAccessor

struct ScrollViewAccessor: UIViewRepresentable {
    let coordinator: ScrollCoordinator

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            if let scrollView = view.findScrollView() {
                coordinator.scrollView = scrollView
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

private extension UIView {
    func findScrollView() -> UIScrollView? {
        if let sv = superview as? UIScrollView { return sv }
        return superview?.findScrollView()
    }
}
