import Foundation

struct ContactInfo: Codable, Sendable {
    var email: String?
    var phone: String?
    var address: String?
    var linkedin: String?
    var github: String?
    var website: String?

    init(email: String? = nil, phone: String? = nil, address: String? = nil,
         linkedin: String? = nil, github: String? = nil, website: String? = nil) {
        self.email = email
        self.phone = phone
        self.address = address
        self.linkedin = linkedin
        self.github = github
        self.website = website
    }
}

struct WorkEntry: Codable, Sendable {
    var company: String
    var title: String?
    var startDate: String?
    var endDate: String?
    var location: String?
    var bullets: [String]

    enum CodingKeys: String, CodingKey {
        case company, title, location, bullets
        case startDate = "start_date"
        case endDate = "end_date"
    }

    init(company: String, title: String? = nil, startDate: String? = nil,
         endDate: String? = nil, location: String? = nil, bullets: [String] = []) {
        self.company = company
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.bullets = bullets
    }
}

struct EducationEntry: Codable, Sendable {
    var institution: String
    var degree: String?
    var field: String?
    var graduationDate: String?
    var gpa: String?

    enum CodingKeys: String, CodingKey {
        case institution, degree, field, gpa
        case graduationDate = "graduation_date"
    }

    init(institution: String, degree: String? = nil, field: String? = nil,
         graduationDate: String? = nil, gpa: String? = nil) {
        self.institution = institution
        self.degree = degree
        self.field = field
        self.graduationDate = graduationDate
        self.gpa = gpa
    }
}

struct WesternResume: Codable, Sendable {
    var name: String?
    var contact: ContactInfo
    var summary: String?
    var experience: [WorkEntry]
    var education: [EducationEntry]
    var skills: [String]
    var certifications: [String]
    var languages: [String]
    var rawSections: [String: String]

    enum CodingKeys: String, CodingKey {
        case name, contact, summary, experience, education, skills
        case certifications, languages
        case rawSections = "raw_sections"
    }

    init(name: String? = nil, contact: ContactInfo = ContactInfo(),
         summary: String? = nil, experience: [WorkEntry] = [],
         education: [EducationEntry] = [], skills: [String] = [],
         certifications: [String] = [], languages: [String] = [],
         rawSections: [String: String] = [:]) {
        self.name = name
        self.contact = contact
        self.summary = summary
        self.experience = experience
        self.education = education
        self.skills = skills
        self.certifications = certifications
        self.languages = languages
        self.rawSections = rawSections
    }
}
