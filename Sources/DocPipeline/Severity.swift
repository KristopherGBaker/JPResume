import Foundation

/// Severity shared by validation issues and artifact warnings. The raw values match the
/// on-disk JSON ("info" / "warning" / "error"), so changing this enum changes the
/// artifact wire format.
public enum Severity: String, Codable, Sendable, CaseIterable {
    case info
    case warning
    case error
}
