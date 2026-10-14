import Foundation

/// 通知授权档位。
///
/// 刻意不暴露 `UNAuthorizationStatus`——这样协议与测试替身都不必 import UserNotifications。
enum DurationAlertAuthorization {
    case notDetermined
    case denied
    case authorized
}

/// 发送系统通知的抽象。
///
/// 真实实现包着 `UNUserNotificationCenter`（有副作用，且在非 bundle 环境有崩溃风险）；
/// 测试注入替身，断言「发了什么」而不真的弹通知。
protocol NotificationPresenting: AnyObject {
    /// 最近一次已知的授权状态，由 refreshAuthorization / requestAuthorization 刷新
    var authorizationStatus: DurationAlertAuthorization { get }

    /// 查询系统设置刷新缓存，**不弹窗**。启动时用。
    /// completion 在主线程回调。
    func refreshAuthorization(completion: @escaping () -> Void)

    /// 请求授权（首次会弹系统弹窗）。completion 在主线程回调，回传是否已授权。
    func requestAuthorization(completion: @escaping (Bool) -> Void)

    /// 立即投递一条通知
    func post(title: String, body: String)

    /// 打开系统设置的「通知」面板
    func openSystemNotificationSettings()

    /// 把自己注册为通知中心的 delegate。必须在发第一条通知之前、app 启动早期调用。
    func installDelegate()
}
