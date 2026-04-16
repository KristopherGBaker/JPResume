import Foundation

/// Options controlling what content is included in JP resume generation.
struct GenerationOptions: Codable, Sendable {
    /// Include personal/side projects in 職務経歴書 work details.
    var includeSideProjects: Bool
    /// Include older roles that may not be relevant to the target position.
    var includeOlderIrrelevantRoles: Bool

    init(includeSideProjects: Bool = false, includeOlderIrrelevantRoles: Bool = true) {
        self.includeSideProjects = includeSideProjects
        self.includeOlderIrrelevantRoles = includeOlderIrrelevantRoles
    }

    enum CodingKeys: String, CodingKey {
        case includeSideProjects = "include_side_projects"
        case includeOlderIrrelevantRoles = "include_older_irrelevant_roles"
    }
}
