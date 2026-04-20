import Foundation

/// Shared `JSONEncoder` configurations used for artifacts, prompts, and cache files.
/// Sorted keys keep on-disk output stable for hashing and diff review; pretty-printing
/// is enabled where humans read the files directly.
enum JSONCoders {
    /// Sorted keys, no pretty-printing. Use when output is hashed or only consumed
    /// programmatically (e.g. inputs to a content hash).
    static var sorted: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }

    /// Sorted keys + pretty-printing. Use for files humans read or edit
    /// (artifacts, prompt bundles, cached AI output).
    static var prettySorted: JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }
}
