import SwiftUI

@main
struct TodoMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("待办", systemImage: "checklist") {
            TodoListView()
                .environmentObject(AppState.shared)
        }
        .menuBarExtraStyle(.window)
    }
}
