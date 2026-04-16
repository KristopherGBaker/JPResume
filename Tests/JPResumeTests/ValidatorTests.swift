import Testing
@testable import jpresume
import Foundation

@Suite("Resume Validator")
struct ValidatorTests {

    // MARK: Helpers

    private func makeResume(
        name: String? = "Jane Doe",
        experience: [NormalizedWorkEntry] = [],
        education: [NormalizedEducationEntry] = [],
        skillCategories: [SkillCategory] = []
    ) -> NormalizedResume {
        NormalizedResume(
            name: name,
            experience: experience,
            education: education,
            skillCategories: skillCategories
        )
    }

    private func work(
        company: String = "Corp",
        start: StructuredDate? = nil,
        end: StructuredDate? = nil,
        isCurrent: Bool = false,
        confidence: Double? = nil
    ) -> NormalizedWorkEntry {
        NormalizedWorkEntry(
            company: company,
            startDate: start,
            endDate: end,
            isCurrent: isCurrent,
            confidence: confidence
        )
    }

    private func edu(
        institution: String = "University",
        start: StructuredDate? = nil,
        grad: StructuredDate? = nil
    ) -> NormalizedEducationEntry {
        NormalizedEducationEntry(
            institution: institution,
            startDate: start,
            graduationDate: grad
        )
    }

    // MARK: Required fields

    @Test func warnsMissingName() {
        let result = ResumeValidator.validate(makeResume(name: nil))
        #expect(result.warnings.contains { $0.field == "name" })
    }

    @Test func warnsEmptyExperience() {
        let result = ResumeValidator.validate(makeResume(experience: []))
        #expect(result.warnings.contains { $0.field == "experience" })
    }

    @Test func warnsEmptyEducation() {
        let result = ResumeValidator.validate(makeResume(education: []))
        #expect(result.warnings.contains { $0.field == "education" })
    }

    @Test func validResumeHasNoIssues() {
        let resume = makeResume(
            experience: [work(start: StructuredDate(year: 2020), isCurrent: true)],
            education: [edu(grad: StructuredDate(year: 2019))]
        )
        let result = ResumeValidator.validate(resume)
        // May still have warnings from missing fields but isValid should be true
        #expect(result.isValid)
    }

    // MARK: Date range validity

    @Test func warnsStartAfterEnd() {
        let entry = work(
            start: StructuredDate(year: 2023, month: 6),
            end: StructuredDate(year: 2020, month: 1)
        )
        let result = ResumeValidator.validate(makeResume(experience: [entry]))
        #expect(result.warnings.contains { $0.field.hasPrefix("experience") && $0.message.contains("after end") })
    }

    @Test func noWarnWhenStartBeforeEnd() {
        let entry = work(
            start: StructuredDate(year: 2020),
            end: StructuredDate(year: 2023)
        )
        let result = ResumeValidator.validate(makeResume(experience: [entry]))
        #expect(!result.warnings.contains { $0.message.contains("after end") })
    }

    // MARK: isCurrent consistency

    @Test func warnsIsCurrentWithEndDate() {
        let entry = work(
            end: StructuredDate(year: 2024, month: 1),
            isCurrent: true
        )
        let result = ResumeValidator.validate(makeResume(experience: [entry]))
        #expect(result.warnings.contains { $0.message.contains("current but has an end date") })
    }

    // MARK: Overlapping roles

    @Test func warnsOverlappingRoles() {
        let a = work(company: "A", start: StructuredDate(year: 2018, month: 1), end: StructuredDate(year: 2022, month: 6))
        let b = work(company: "B", start: StructuredDate(year: 2020, month: 1), end: StructuredDate(year: 2023, month: 1))
        let result = ResumeValidator.validate(makeResume(experience: [a, b]))
        #expect(result.warnings.contains { $0.message.contains("Overlapping") })
    }

    @Test func noWarnSequentialRoles() {
        let a = work(company: "A", start: StructuredDate(year: 2018), end: StructuredDate(year: 2020))
        let b = work(company: "B", start: StructuredDate(year: 2020), end: StructuredDate(year: 2023))
        let result = ResumeValidator.validate(makeResume(experience: [a, b]))
        #expect(!result.warnings.contains { $0.message.contains("Overlapping") })
    }

    // MARK: Low confidence

    @Test func warnsLowConfidence() {
        let entry = work(start: StructuredDate(year: 2020), confidence: 0.4)
        let result = ResumeValidator.validate(makeResume(experience: [entry]))
        #expect(result.warnings.contains { $0.message.contains("low normalization confidence") })
    }

    @Test func noWarnHighConfidence() {
        let entry = work(start: StructuredDate(year: 2020), confidence: 0.9)
        let result = ResumeValidator.validate(makeResume(experience: [entry]))
        #expect(!result.warnings.contains { $0.message.contains("confidence") })
    }

    // MARK: Skill categorization

    @Test func warnsAllSkillsInOther() {
        let resume = makeResume(skillCategories: [SkillCategory(name: "Other", skills: ["Swift"])])
        let result = ResumeValidator.validate(resume)
        #expect(result.warnings.contains { $0.field == "skill_categories" })
    }

    @Test func noWarnProperCategories() {
        let resume = makeResume(skillCategories: [
            SkillCategory(name: "Languages", skills: ["Swift"]),
            SkillCategory(name: "Frameworks", skills: ["SwiftUI"])
        ])
        let result = ResumeValidator.validate(resume)
        #expect(!result.warnings.contains { $0.field == "skill_categories" })
    }

    // MARK: Total years

    @Test func computesTotalYears() {
        let entries = [
            work(start: StructuredDate(year: 2018, month: 1), end: StructuredDate(year: 2020, month: 1)),
            work(start: StructuredDate(year: 2020, month: 6), end: StructuredDate(year: 2022, month: 6))
        ]
        let result = ResumeValidator.validate(makeResume(experience: entries))
        #expect(result.totalYearsExperience != nil)
        // 24 months + 24 months = 48 months = 4.0 years
        #expect(abs((result.totalYearsExperience ?? 0) - 4.0) < 0.1)
    }

    @Test func totalYearsNilForEntriesWithoutDates() {
        let result = ResumeValidator.validate(makeResume(experience: [work()]))
        #expect(result.totalYearsExperience == nil)
    }
}
