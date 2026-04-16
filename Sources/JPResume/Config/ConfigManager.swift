import Foundation
import Yams

enum ConfigManager {
    static func load(from path: URL) throws -> JapanConfig? {
        guard FileManager.default.fileExists(atPath: path.path) else {
            return nil
        }
        let yaml = try String(contentsOf: path, encoding: .utf8)
        let decoder = YAMLDecoder()
        return try decoder.decode(JapanConfig.self, from: yaml)
    }

    static func save(_ config: JapanConfig, to path: URL) throws {
        let encoder = YAMLEncoder()
        let yaml = try encoder.encode(config)
        try yaml.write(to: path, atomically: true, encoding: .utf8)
        print("  Config saved to \(path.path)")
    }

    static func loadOrPrompt(path: URL, western: WesternResume, forceReconfigure: Bool) throws -> JapanConfig {
        if !forceReconfigure, let config = try load(from: path) {
            print("  Using saved config from \(path.path)")
            return config
        }

        print("\n  No configuration found. Let's gather your Japan-specific information.")
        print("  This will be saved for future use.\n")

        let config = InteractivePrompter.promptAll(western: western)
        try save(config, to: path)
        return config
    }
}
