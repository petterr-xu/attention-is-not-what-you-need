import SwiftUI

@main
struct AttentionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // 菜单栏图标与待办面板都交给 AppDelegate 用 NSStatusItem / NSPopover 管理
        // （需要区分左右键，MenuBarExtra 做不到）。
        // SwiftUI 的 App 要求至少有一个 Scene，这里放一个空的占位。
        Settings {
            EmptyView()
        }
    }
}
