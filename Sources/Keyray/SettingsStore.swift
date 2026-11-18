import KeyrayCore
import Foundation

/// The live settings, persisted as one JSON blob in the app's (sandboxed) user defaults.
@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "settings.v1"
    private let defaults: UserDefaults

    @Published var settings: AppSettings {
        didSet {
            if settings != settings.normalized { settings = settings.normalized; return }
            if let data = try? settings.encoded() { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settings = AppSettings.decoded(from: defaults.data(forKey: Self.key))
    }
}
