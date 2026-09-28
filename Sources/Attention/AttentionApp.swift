import SwiftUI

@main
struct AttentionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Attention", systemImage: "checklist") {
            TodoListView()
                .environmentObject(AppState.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
