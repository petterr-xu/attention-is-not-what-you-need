import SwiftUI
import Foundation

/// 水平阻尼抖动。
///
/// `progress` 由 SwiftUI 在 0→1 之间插值；`sin` 在 progress 为 0 和 1 处都为 0，
/// 所以**模型值本身永远落在「零位移」的刻度上**——动画结束、或被中途打断复位时，
/// 位移恒为 0，图标精确回到原位。
///
/// 这正是不用 `repeatCount(autoreverses:)` 的原因：那种写法会把模型值留在目标值上，
/// 动画播完图标永久歪着；而 macOS 13 又没有 `AnimationCompletionCriteria` 之类的
/// 收尾钩子，打断后状态机就失步了。
///
/// 用变换而不是 `.offset`：变换不触发布局重排，图标所在的 HStack 不会跟着抖。
struct ShakeEffect: GeometryEffect {
    /// 由整数脉冲驱动：每次 +1 就是一次抖动
    var progress: CGFloat
    var amplitude: CGFloat = 6
    var shakes: CGFloat = 3

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// 抽成静态纯函数，便于单测端点（视图本身不进单测）
    static func offset(progress: CGFloat,
                       amplitude: CGFloat = 6,
                       shakes: CGFloat = 3) -> CGFloat {
        amplitude * sin(progress * shakes * 2 * .pi)
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(
            translationX: Self.offset(progress: progress, amplitude: amplitude, shakes: shakes),
            y: 0))
    }
}
