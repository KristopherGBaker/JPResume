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
    /// True if this entry is a personal/side/hobby project rather than salaried employment.
    var isSideProject: Bool?
    /// True if this entry is a salaried professional role. Usually the inverse of isSideProject.
    var isProfessionalRole: Bool?
    /// Short specialization tags (e.g. "ios", "backend", "leadership"). Used by downstream prompts
    /// to decide how to frame the role.
    var specializationTags: [String]?

    enum CodingKeys: String, CodingKey {
        case company, title, location, bullets, confidence
        case startDate = "start_date"
        case endDate = "end_date"
        case isCurrent = "is_current"
        case isSideProject = "is_side_project"
        case isProfessionalRole = "is_professional_role"
        case specializationTags = "specialization_tags"
    }

    init(
        company: String,
        title: String? = nil,
        startDate: StructuredDate? = nil,
        endDate: StructuredDate? = nil,
        isCurrent: Bool = false,
        location: String? = nil,
        bullets: [NormalizedBullet] = [],
        confidence: Double? = nil,
        isSideProject: Bool? = nil,
        isProfessionalRole: Bool? = nil,
        specializationTags: [String]? = nil
    ) {
        self.company = company
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.isCurrent = isCurrent
        self.location = location
        self.bullets = bullets
        self.confidence = confidence
        self.isSideProject = isSideProject
        self.isProfessionalRole = isProfessionalRole
        self.specializationTags = specializationTags
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

// MARK: - DerivedExperience

/// Computed experience metrics derived from the normalized timeline.
/// Values here override any LLM-generated prose about years of experience.
struct DerivedExperience: Codable, Sendable {
    /// Total professional software years (earliest start to latest/current).
    var totalSoftwareYears: Int
    /// iOS-focused years (roles with iOS/Swift/mobile in title or bullets).
    var iosYears: Int?
    /// Whether any role involved international/cross-border team collaboration.
    var hasInternationalTeamExperience: Bool
    /// Years spent in Japan-based roles specifically.
    var jpWorkYears: Int?

    enum CodingKeys: String, CodingKey {
        case totalSoftwareYears = "total_software_years"
        case iosYears = "ios_years"
        case hasInternationalTeamExperience = "has_international_team_experience"
        case jpWorkYears = "jp_work_years"
    }

    init(
        totalSoftwareYears: Int = 0,
        iosYears: Int? = nil,
        hasInternationalTeamExperience: Bool = false,
        jpWorkYears: Int? = nil
    ) {
        self.totalSoftwareYears = totalSoftwareYears
        self.iosYears = iosYears
        self.hasInternationalTeamExperience = hasInternationalTeamExperience
        self.jpWorkYears = jpWorkYears
    }
}

// MARK: - RepairNote

/// Records a safe repair applied to normalized data during consistency checking.
struct RepairNote: Codable, Sendable {
    var field: String
    var original: String
    var repaired: String
    var reason: String
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
    /// Computed experience metrics derived from the timeline. Populated by ResumeConsistencyChecker.
    /// The LLM may also emit an initial estimate in the normalization response; the checker
    /// recomputes these deterministically — chronology wins over any prose claims.
    var derivedExperience: DerivedExperience?
    /// LLM-flagged timeline concerns (overlaps, suspicious gaps, prose/chronology conflicts).
    /// Preserved through the pipeline so downstream prompts can see what was surprising.
    var timelineWarnings: [String]?
    /// Repairs applied during consistency checking.
    var repairs: [RepairNote]

    enum CodingKeys: String, CodingKey {
        case name, contact, summary, experience, education, certifications, languages, repairs
        case skillCategories = "skill_categories"
        case normalizerNotes = "normalizer_notes"
        case rawSections = "raw_sections"
        case derivedExperience = "derived_experience"
        case timelineWarnings = "timeline_warnings"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        contact = (try? c.decode(ContactInfo.self, forKey: .contact)) ?? ContactInfo()
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        experience = (try? c.decode([NormalizedWorkEntry].self, forKey: .experience)) ?? []
        education = (try? c.decode([NormalizedEducationEntry].self, forKey: .education)) ?? []
        skillCategories = (try? c.decode([SkillCategory].self, forKey: .skillCategories)) ?? []
        certifications = (try? c.decode([String].self, forKey: .certifications)) ?? []
        languages = (try? c.decode([String].self, forKey: .languages)) ?? []
        normalizerNotes = (try? c.decode([String].self, forKey: .normalizerNotes)) ?? []
        rawSections = (try? c.decode([String: String].self, forKey: .rawSections)) ?? [:]
        derivedExperience = try? c.decodeIfPresent(DerivedExperience.self, forKey: .derivedExperience)
        timelineWarnings = try? c.decodeIfPresent([String].self, forKey: .timelineWarnings)
        repairs = (try? c.decode([RepairNote].self, forKey: .repairs)) ?? []
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
        rawSections: [String: String] = [:],
        derivedExperience: DerivedExperience? = nil,
        timelineWarnings: [String]? = nil,
        repairs: [RepairNote] = []
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
        self.derivedExperience = derivedExperience
        self.timelineWarnings = timelineWarnings
        self.repairs = repairs
    }
}
