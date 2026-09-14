import Foundation

struct CompanyDetail: Codable, Sendable {
    var companyName: String
    var period: String
    var industry: String?
    var companySize: String?
    var employmentType: String?
    var role: String?
    var department: String?
    var responsibilities: [String]
    var achievements: [String]

    enum CodingKeys: String, CodingKey {
        case period, industry, role, department, responsibilities, achievements
        case companyName = "company_name"
        case companySize = "company_size"
        case employmentType = "employment_type"
    }

    init(companyName: String, period: String, industry: String? = nil,
         companySize: String? = nil, employmentType: String? = nil,
         role: String? = nil, department: String? = nil,
         responsibilities: [String] = [], achievements: [String] = []) {
        self.companyName = companyName
        self.period = period
        self.industry = industry
        self.companySize = companySize
        self.employmentType = employmentType
        self.role = role
        self.department = department
        self.responsibilities = responsibilities
        self.achievements = achievements
    }
}

struct ShokumukeirekishoData: Codable, Sendable {
    var creationDate: String
    var name: String
    var careerSummary: String
    var workDetails: [CompanyDetail]
    var technicalSkills: [String: [String]]
    var selfPr: String?

    enum CodingKeys: String, CodingKey {
        case name
        case creationDate = "creation_date"
        case careerSummary = "career_summary"
        case workDetails = "work_details"
        case technicalSkills = "technical_skills"
        case selfPr = "self_pr"
    }

    /// The skill taxonomy the generator is told to use, in the order a Japanese reader
    /// expects: concrete first (languages, frameworks), practice next, catch-all last.
    static let skillCategoryOrder = ["言語", "フレームワーク", "設計・開発", "品質・改善", "AI関連", "その他"]

    /// `technicalSkills` is a dictionary, so iterating it directly renders the categories
    /// in hash order — a different order on every run. Renderers use this instead:
    /// known categories in taxonomy order, then any others alphabetically.
    var orderedTechnicalSkills: [(category: String, skills: [String])] {
        let order = Self.skillCategoryOrder
        return technicalSkills
            .sorted { lhs, rhs in
                switch (order.firstIndex(of: lhs.key), order.firstIndex(of: rhs.key)) {
                case let (l?, r?): return l < r
                case (_?, nil): return true
                case (nil, _?): return false
                case (nil, nil): return lhs.key < rhs.key
                }
            }
            .map { (category: $0.key, skills: $0.value) }
    }
}
