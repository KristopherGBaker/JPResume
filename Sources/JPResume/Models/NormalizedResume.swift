import Foundation

// MARK: - StructuredDate

struct StructuredDate: Codable, Sendable {
    var year: Int
    var month: Int?

    init(year: Int, month: Int? = nil) {
        self.year = year
        self.month = month
    }
}

extension StructuredDate: Comparable {
    static func < (lhs: StructuredDate, rhs: StructuredDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        let lm = lhs.month ?? 1
        let rm = rhs.month ?? 12
        return lm < rm
    }
}

// MARK: - NormalizedBullet

struct NormalizedBullet: Codable, Sendable {
    var text: String
    var category: BulletCategory

    enum BulletCategory: String, Codable, Sendable {
        case responsibility
        case achievement
    }

    enum CodingKeys: String, CodingKey {
        case text, category
    }

    init(text: String, category: BulletCategory = .responsibility) {
        self.text = text
        self.category = category
    }
}

// MARK: - NormalizedWorkEntry

struct NormalizedWorkEntry: Codable, Sendable {
    var company: String
    var title: String?
    var startDate: StructuredDate?
    var endDate: StructuredDate?
    var isCurrent: Bool
    var location: String?
    var bullets: [NormalizedBullet]
    /// 0.0–1.0 confidence in date parsing and bullet classification. Omitted when unambiguous.
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case company, title, location, bullets, confidence
        case startDate = "start_date"
        case endDate = "end_date"
        case isCurrent = "is_current"
    }

    init(
        company: String,
        title: String? = nil,
        startDate: StructuredDate? = nil,
        endDate: StructuredDate? = nil,
        isCurrent: Bool = false,
        location: String? = nil,
        bullets: [NormalizedBullet] = [],
        confidence: Double? = nil
    ) {
        self.company = company
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isCurrent = isCurrent
        self.location = location
        self.bullets = bullets
        self.confidence = confidence
    }
}

// MARK: - NormalizedEducationEntry

struct NormalizedEducationEntry: Codable, Sendable {
    var institution: String
    var degree: String?
    var field: String?
    var startDate: StructuredDate?
    var graduationDate: StructuredDate?
    var gpa: String?
    /// 0.0–1.0 confidence in date parsing. Omitted when unambiguous.
    var confidence: Double?

    enum CodingKeys: String, CodingKey {
        case institution, degree, field, gpa, confidence
        case startDate = "start_date"
        case graduationDate = "graduation_date"
    }

    init(
        institution: String,
        degree: String? = nil,
        field: String? = nil,
        startDate: StructuredDate? = nil,
        graduationDate: StructuredDate? = nil,
        gpa: String? = nil,
        confidence: Double? = nil
    ) {
        self.institution = institution
        self.degree = degree
        self.field = field
        self.startDate = startDate
        self.graduationDate = graduationDate
        self.gpa = gpa
        self.confidence = confidence
    }
}

// MARK: - SkillCategory

struct SkillCategory: Codable, Sendable {
    var name: String
    var skills: [String]
}

// MARK: - NormalizedResume

struct NormalizedResume: Codable, Sendable {
    var name: String?
    var contact: ContactInfo
    var summary: String?
    var experience: [NormalizedWorkEntry]
    var education: [NormalizedEducationEntry]
    var skillCategories: [SkillCategory]
    var certifications: [String]
    var languages: [String]
    /// Free-text notes from the LLM about ambiguities or assumptions made during normalization.
    var normalizerNotes: [String]
    var rawSections: [String: String]

    enum CodingKeys: String, CodingKey {
        case name, contact, summary, experience, education, certifications, languages
        case skillCategories = "skill_categories"
        case normalizerNotes = "normalizer_notes"
        case rawSections = "raw_sections"
    }

    init(
        name: String? = nil,
        contact: ContactInfo = ContactInfo(),
        summary: String? = nil,
        experience: [NormalizedWorkEntry] = [],
        education: [NormalizedEducationEntry] = [],
        skillCategories: [SkillCategory] = [],
        certifications: [String] = [],
        languages: [String] = [],
        normalizerNotes: [String] = [],
        rawSections: [String: String] = [:]
    ) {
        self.name = name
        self.contact = contact
        self.summary = summary
        self.experience = experience
        self.education = education
        self.skillCategories = skillCategories
        self.certifications = certifications
        self.languages = languages
        self.normalizerNotes = normalizerNotes
        self.rawSections = rawSections
    }
}
