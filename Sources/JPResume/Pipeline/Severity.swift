import Foundation

/// Severity used by both validation issues and artifact warnings. The raw values
/// match the on-disk JSON ("info" / "warning" / "error") so changing this enum
/// would change the artifact wire format.
enum Severity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case error
}
