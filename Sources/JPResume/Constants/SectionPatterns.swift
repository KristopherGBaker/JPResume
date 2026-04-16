import Foundation

enum SectionCategory: String, Sendable {
    case summary, experience, education, skills, certifications, languages
    case projects, awards, publications, volunteer
}

enum SectionClassifier {
    static let patterns: [SectionCategory: [String]] = [
        .summary: [
            "summary", "profile", "objective", "about", "overview",
            "professional summary", "career objective",
        ],
        .experience: [
            "experience", "work experience", "professional experience",
            "employment", "work history", "career history",
        ],
        .education: [
            "education", "academic", "qualifications",
        ],
        .skills: [
            "skills", "technical skills", "technologies", "competencies",
            "core competencies", "technical competencies",
            "languages & platforms",
        ],
        .certifications: [
            "certifications", "certificates", "licenses",
            "certifications and licenses", "professional certifications",
        ],
        .languages: [
            "languages", "language skills",
        ],
        .projects: [
            "projects", "personal projects", "side projects",
        ],
        .awards: [
            "awards", "honors", "achievements",
        ],
        .publications: [
            "publications", "papers",
        ],
        .volunteer: [
            "volunteer", "volunteering", "community",
        ],
    ]

    static func classify(_ heading: String) -> SectionCategory? {
        let lower = heading.lowercased().trimmingCharacters(in: .whitespaces)
        for (category, keywords) in patterns {
            for pattern in keywords {
                if lower == pattern || lower.hasPrefix(pattern) {
                    return category
                }
            }
        }
        return nil
    }
}
