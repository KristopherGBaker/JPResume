import Foundation

/// A single rule violation surfaced by a deterministic, domain-specific output checker.
/// The framework defines the shape; each pipeline supplies its own checker that returns
/// these. Violations are intentionally surfaced as data rather than auto-fixed: the
/// self-critique loop feeds them back to the LLM as the next pass's instructions.
public struct ConstraintViolation: Sendable, Equatable {
    public let rule: String      // stable ID — keeps tests + critique prompts in sync
    public let field: String     // the artifact field the violation lives in
    public let message: String   // human-readable description, also fed to the LLM

    public init(rule: String, field: String, message: String) {
        self.rule = rule
        self.field = field
        self.message = message
    }
}
