import SwiftUI

@main
struct LittleWatchApp: App {
    @StateObject private var store = AppStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            Text(store.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsRootView(store: store)
                .frame(minWidth: 880, idealWidth: 940, minHeight: 610, idealHeight: 660)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 940, height: 660)
        .windowResizability(.contentMinSize)
    }
}
