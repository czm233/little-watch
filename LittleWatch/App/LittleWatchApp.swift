import SwiftUI

@main
struct LittleWatchApp: App {
    @StateObject private var store = AppStore()
    @AppStorage(SourceSetupOnboarding.completionKey) private var hasCompletedSourceSetup = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store)
        } label: {
            Text(menuBarTitle)
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

    private var menuBarTitle: String {
        if hasCompletedSourceSetup || store.isSourceConnected {
            return store.menuBarTitle
        }
        return "Little Watch"
    }
}
