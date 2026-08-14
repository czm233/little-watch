import SwiftUI

@MainActor
enum SourceSetupOnboarding {
    static let completionKey = "littlewatch.onboarding.source-setup-completed.v1"

    static func bootstrap(
        for store: AppStore,
        defaults: UserDefaults = .standard
    ) -> Bool {
        if let storedValue = defaults.object(forKey: completionKey) as? Bool {
            return storedValue
        }

        // Existing installations with a complete configuration should not be
        // sent through first-run setup after upgrading.
        let inferredCompletion = store.hasConfiguredSource && store.hasStoredCredential
        defaults.set(inferredCompletion, forKey: completionKey)
        return inferredCompletion
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: completionKey)
    }
}

struct SettingsRootView: View {
    @ObservedObject var store: AppStore
    @AppStorage(SourceSetupOnboarding.completionKey) private var hasCompletedSourceSetup = false
    @State private var selection: SettingsSection

    init(store: AppStore) {
        self.store = store
        let hasCompletedSourceSetup = SourceSetupOnboarding.bootstrap(for: store)
        _hasCompletedSourceSetup = AppStorage(
            wrappedValue: hasCompletedSourceSetup,
            SourceSetupOnboarding.completionKey
        )
        _selection = State(initialValue: hasCompletedSourceSetup ? .menuBar : .sources)
    }

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
                case .usage:
                    UsageInsightsView(store: store)
                case .sources:
                    SourcesPlaceholderView(
                        store: store,
                        showsOnboarding: !hasCompletedSourceSetup
                    ) {
                        SourceSetupOnboarding.markCompleted()
                        hasCompletedSourceSetup = true
                    }
                }
            }
        }
        .background(LittleWatchTheme.canvas)
    }
}
