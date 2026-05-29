import Foundation

/// Output of a generate stage that ran through the self-critique loop. Carries any
/// violations that remained after the last critique pass so the caller can surface them
/// as artifact warnings.
public struct GenerationResult<T: Sendable>: Sendable {
    public let data: T
    public let critiquePasses: Int
    public let remainingViolations: [ConstraintViolation]

    public init(data: T, critiquePasses: Int, remainingViolations: [ConstraintViolation]) {
        self.data = data
        self.critiquePasses = critiquePasses
        self.remainingViolations = remainingViolations
    }

    public var asArtifactWarnings: [ArtifactWarning] {
        remainingViolations.map { v in
            ArtifactWarning(severity: .warning, field: v.field,
                            message: "[\(v.rule)] \(v.message)")
        }
    }
}
