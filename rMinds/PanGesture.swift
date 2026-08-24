import SwiftUI
import UIKit

/// 原生平移手势（UIGestureRecognizerRepresentable，iOS 18+）。
/// 规避 SwiftUI simultaneousGesture(DragGesture) 与 ScrollView 的手势合成器冲突
/// （FB18199844，iOS 26 引入、27 仍存在：滚动被吞/首滑失灵）。
/// delegate 放行并行识别，竖向滚动与横向行滑动互不抢触摸。
struct PanGesture: UIGestureRecognizerRepresentable {
    typealias UIGestureRecognizerType = UIPanGestureRecognizer

    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint, CGFloat) -> Void   // 结束点位置 + x 方向速度(pt/s)

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.parent = self
    }

    func handleUIGestureRecognizerAction(
        _ recognizer: UIPanGestureRecognizer,
        context: Context
    ) {
        guard let view = recognizer.view else { return }
        let location = recognizer.location(in: view)
        switch recognizer.state {
        case .began:
            context.coordinator.parent.onBegan(location)
        case .changed:
            context.coordinator.parent.onChanged(location)
        case .ended:
            context.coordinator.parent.onEnded(location, recognizer.velocity(in: view).x)
        default:
            context.coordinator.parent.onEnded(location, 0)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: PanGesture
        init(parent: PanGesture) { self.parent = parent }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool { true }
    }
}
