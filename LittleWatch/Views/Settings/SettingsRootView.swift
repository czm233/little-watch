import SwiftUI

struct SettingsRootView: View {
    @ObservedObject var store: AppStore
    @State private var selection: SettingsSection = .menuBar

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(
                selection: $selection,
                sourceName: store.sourceName,
                isSourceConnected: store.isSourceConnected
            )

            ZStack {
                LittleWatchTheme.canvas

                Circle()
                    .fill(LittleWatchTheme.signal.opacity(0.045))
                    .frame(width: 420, height: 420)
                    .blur(radius: 90)
                    .offset(x: 270, y: -270)

                switch selection {
                case .menuBar:
                    MenuBarConfigurationView(store: store)
                case .sources:
                    SourcesPlaceholderView(store: store)
                }
            }
        }
        .background(LittleWatchTheme.canvas)
    }
}
