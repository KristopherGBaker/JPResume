import Foundation

enum AICache {
    static func load<T: Decodable>(from url: URL) -> T? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(T.self, from: data) else {
            return nil
        }
        return result
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url)
        print("  Cached to \(url.path)")
    }
}
