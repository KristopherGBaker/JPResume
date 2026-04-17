import Foundation

/// Optional target-company layer for tailored application documents.
/// When provided, prompts adjust 志望動機, 職務要約, 自己PR, and role emphasis
/// toward the specified employer and role without inventing unsupported claims.
struct TargetCompanyContext: Codable, Sendable {
    var companyName: String?
    var roleTitle: String?
    var companySummary: String?
    var jobDescriptionExcerpt: String?
    var normalizedRequirements: [String]?
    /// Short tags signaling the most relevant dimensions of the target role.
    /// Examples: "consumer", "mobile", "growth", "platform", "ai", "global", "b2b"
    var emphasisTags: [String]?
    var candidateInterestNotes: String?

    enum CodingKeys: String, CodingKey {
        case companyName = "company_name"
        case roleTitle = "role_title"
        case companySummary = "company_summary"
        case jobDescriptionExcerpt = "job_description_excerpt"
        case normalizedRequirements = "normalized_requirements"
        case emphasisTags = "emphasis_tags"
        case candidateInterestNotes = "candidate_interest_notes"
    }
}
