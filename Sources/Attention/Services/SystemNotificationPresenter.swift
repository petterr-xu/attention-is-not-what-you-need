import AppKit
import Foundation
import UserNotifications

/// 基于 UserNotifications 的通知发送实现。
///
/// 这个 app 是「菜单栏 app（LSUIElement）+ ad-hoc 自签」，有几个坑要专门防：
///
/// 1. `UNUserNotificationCenter.current()` 在**非 bundle 环境**（`swift run` 产出的是裸
///    Mach-O，`bundleIdentifier == nil`）会抛 ObjC 异常，Swift 的 `do/catch` 抓不住、直接崩。
///    所以 `center` 是**懒计算属性**且先判 bundle——构造本对象时绝不碰 UN。
/// 2. delegate 是 weak，必须自己强引用（就是本对象）。
/// 3. **设了 delegate 却不实现 `willPresent`，前台通知会被静音**——比完全不设 delegate 还糟
///    （不设时系统用通知原始 options，横幅照常显示）。所以下面实现了它。
final class SystemNotificationPresenter: NSObject, NotificationPresenting {
    private let available = Bundle.main.bundleIdentifier != nil
    private var cached: DurationAlertAuthorization = .notDetermined

    /// 懒计算：构造时不触碰 UNUserNotificationCenter（测试里会构造本对象）
    private var center: UNUserNotificationCenter? {
        available ? UNUserNotificationCenter.current() : nil
    }

    var authorizationStatus: DurationAlertAuthorization { cached }

    func refreshAuthorization(completion: @escaping () -> Void) {
        guard let center else {
            DispatchQueue.main.async { completion() }
            return
        }
        center.getNotificationSettings { settings in
            let status = Self.map(settings.authorizationStatus)
            DispatchQueue.main.async {
                self.cached = status
                completion()
            }
        }
    }

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard let center else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            DispatchQueue.main.async {
                self.cached = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }

    func post(title: String, body: String) {
        guard let center else { return }   // swift run：静默降级，不崩

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // identifier 是主键，同 id 的请求会互相替换——所以用 UUID，不拿任务 id 当
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)   // nil = 立即投递
        center.add(request) { error in
            if let error { NSLog("[Attention] 通知投递失败：\(error)") }
        }
    }

    func openSystemNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func installDelegate() {
        center?.delegate = self
    }

    private static func map(_ status: UNAuthorizationStatus) -> DurationAlertAuthorization {
        switch status {
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        default: return .authorized
        }
    }
}

extension SystemNotificationPresenter: UNUserNotificationCenterDelegate {
    /// 必须实现：设了 delegate 却没实现它，前台通知会被静音（官方文档明确说明）。
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                    @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
