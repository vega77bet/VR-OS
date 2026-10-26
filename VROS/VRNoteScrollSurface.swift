import SwiftUI
import UIKit

/// Per-window scroll state shared by the left and right eye. Both UITextViews
/// show the same text and offset, while only the left eye receives touch input.
/// A pinch scroll can update the exact pixel offset without guessing which
/// paragraph was visible.
@MainActor
final class VRNoteSession: ObservableObject {
    @Published var text: String

    weak var primary: UITextView?
    weak var secondary: UITextView?
    private(set) var offsetY: CGFloat = 0

    init(text: String) {
        self.text = text
    }

    func scrollBy(_ delta: CGFloat) {
        scroll(to: offsetY + delta)
    }

    func scrollFromPinch(startY: CGFloat, fingerDeltaY: CGFloat) {
        scroll(to: startY - fingerDeltaY * 1.4)
    }

    func scroll(to requestedY: CGFloat) {
        guard let primary = primary else { return }
        let insets = primary.adjustedContentInset
        let minY = -insets.top
        let maxY = max(minY, primary.contentSize.height -
                              primary.bounds.height + insets.bottom)
        let position = max(minY, min(maxY, requestedY))
        offsetY = position
        for view in [primary, secondary].compactMap({ $0 }) {
            let ownInset = view.adjustedContentInset
            let ownMax = max(-ownInset.top, view.contentSize.height -
                            view.bounds.height + ownInset.bottom)
            let limited = max(-ownInset.top, min(ownMax, position))
            if abs(view.contentOffset.y - limited) > 0.5 {
                view.setContentOffset(CGPoint(x: 0, y: limited), animated: false)
            }
        }
    }

    func didScroll(_ view: UITextView) {
        guard view === primary else { return }
        let y = view.contentOffset.y
        offsetY = y
        if let secondary = secondary,
           abs(secondary.contentOffset.y - y) > 0.5 {
            secondary.setContentOffset(CGPoint(x: 0, y: y), animated: false)
        }
    }
}

struct VRNoteScrollSurface: UIViewRepresentable {
    @ObservedObject var session: VRNoteSession
    let rightEye: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(frame: .zero)
        view.backgroundColor = .clear
        view.textColor = .white
        view.font = .systemFont(ofSize: 12)
        view.text = session.text
        view.isEditable = false
        view.isSelectable = false
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = !rightEye
        view.textContainerInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 5)
        view.textContainer.lineFragmentPadding = 0
        view.contentInsetAdjustmentBehavior = .never
        view.delegate = context.coordinator
        view.isUserInteractionEnabled = !rightEye
        view.accessibilityLabel = "Texto da janela, role para ler"
        if rightEye {
            session.secondary = view
        } else {
            session.primary = view
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != session.text {
            view.text = session.text
        }
        if abs(view.contentOffset.y - session.offsetY) > 1 {
            view.setContentOffset(CGPoint(x: 0, y: session.offsetY),
                                  animated: false)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let session: VRNoteSession

        init(session: VRNoteSession) {
            self.session = session
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard let view = scrollView as? UITextView else { return }
            session.didScroll(view)
        }
    }
}
