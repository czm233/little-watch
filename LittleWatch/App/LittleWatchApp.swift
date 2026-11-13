import SwiftUI

@main
struct LittleWatchApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var audioStore = AudioStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(store: store, audioStore: audioStore)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: audioStore.outputMuted ? "line.horizontal.3" : "waveform")
                    .symbolRenderingMode(.hierarchical)
                Text(store.menuBarTitle)
                    .monospacedDigit()
            }
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
