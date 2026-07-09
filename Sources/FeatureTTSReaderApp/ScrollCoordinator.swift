import SwiftUI

// MARK: - ScrollCoordinator (for programmatic scroll-to-offset)

@MainActor
class ScrollCoordinator: ObservableObject {
    weak var scrollView: UIScrollView?

    func scrollTo(offset: CGFloat, animated: Bool = true) {
        if let sv = scrollView {
            let maxOffset = max(0, sv.contentSize.height - sv.bounds.height)
            let clamped = min(max(offset, 0), maxOffset)
            sv.setContentOffset(CGPoint(x: 0, y: clamped), animated: animated)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.scrollTo(offset: offset, animated: animated)
        }
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
