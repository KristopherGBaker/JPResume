import Foundation

/// Output of a generate stage that ran through the critique loop. Carries any
/// violations that remained after the last critique pass so the caller can surface
/// them as artifact warnings.
struct GenerationResult<T: Sendable>: Sendable {
    let data: T
    let critiquePasses: Int
    let remainingViolations: [ConstraintViolation]

    var asArtifactWarnings: [ArtifactWarning] {
        remainingViolations.map { v in
            ArtifactWarning(severity: .warning, field: v.field,
                            message: "[\(v.rule)] \(v.message)")
        }
    }
}
