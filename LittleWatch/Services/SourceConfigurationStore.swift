import Foundation

struct SourceConfigurationStore {
    private let defaults: UserDefaults
    private let key = "littlewatch.source.cpa-usage-keeper.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> SourceConfiguration {
        guard
            let data = defaults.data(forKey: key),
            let configuration = try? JSONDecoder().decode(SourceConfiguration.self, from: data)
        else {
            return .default
        }
        return configuration
    }

    func save(_ configuration: SourceConfiguration) {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: key)
    }
}
