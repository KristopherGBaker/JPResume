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
}
