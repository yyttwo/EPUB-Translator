import Foundation

enum AppIdentity {
    static let bundleIdentifier = "com.example.EPUBTranslatorAppStore.Dev"
    static let displayName = "EPUB翻译"
    static let stateDirectoryName = "EPUBTranslatorAppStoreDev"
    static let preferencesSuite = "com.example.EPUBTranslatorAppStore.Dev.preferences.v1"
    static let helperName = "EPUBTranslatorHelper"
}

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case qwen = "Qwen"
    case deepSeek = "DeepSeek"

    var id: String { rawValue }

    init?(userEnteredName: String) {
        let normalized = userEnteredName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
        switch normalized {
        case "qwen", "千问", "通义千问": self = .qwen
        case "deepseek", "深度求索": self = .deepSeek
        default: return nil
        }
    }
}

struct AppPaths {
    let applicationSupport: URL
    let caches: URL
    let temporary: URL

    static func live(fileManager: FileManager = .default) throws -> AppPaths {
        let supportRoot = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let cacheRoot = try fileManager.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AppPaths(
            applicationSupport: supportRoot.appendingPathComponent(AppIdentity.stateDirectoryName, isDirectory: true),
            caches: cacheRoot.appendingPathComponent(AppIdentity.stateDirectoryName, isDirectory: true),
            temporary: fileManager.temporaryDirectory.appendingPathComponent(AppIdentity.stateDirectoryName, isDirectory: true)
        )
    }

    func createRequiredDirectories(fileManager: FileManager = .default) throws {
        for url in [applicationSupport, caches, temporary] {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}

final class ProviderPreferenceStore {
    private let defaults: UserDefaults
    private let key = "selectedProvider"
    private let styleKey = "selectedTranslationStyle"

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppIdentity.preferencesSuite)) {
        self.defaults = defaults ?? .standard
    }

    var selectedProvider: ProviderID {
        get { ProviderID(rawValue: defaults.string(forKey: key) ?? "") ?? .qwen }
        set { defaults.set(newValue.rawValue, forKey: key) }
    }

    var selectedStyle: TranslationStyle {
        get {
            TranslationStyle(rawValue: defaults.string(forKey: styleKey) ?? "")
                ?? TranslationStylePromptRegistry.defaultStyle
        }
        set { defaults.set(newValue.rawValue, forKey: styleKey) }
    }

}
