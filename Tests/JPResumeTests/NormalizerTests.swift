import Testing
@testable import jpresume
import Foundation

@Suite("Normalizer Models")
struct NormalizerModelTests {

    // MARK: StructuredDate

    @Test func structuredDateComparableByYear() {
        let earlier = StructuredDate(year: 2018)
        let later = StructuredDate(year: 2022)
        #expect(earlier < later)
        #expect(later > earlier)
        #expect(earlier == StructuredDate(year: 2018))
    }

    @Test func structuredDateComparableByMonth() {
        let jan = StructuredDate(year: 2020, month: 1)
        let dec = StructuredDate(year: 2020, month: 12)
        #expect(jan < dec)
    }

    @Test func structuredDateMissingMonthUsesConservativeDefault() {
        // Year-only start should be < year-only end
        let start = StructuredDate(year: 2020)
        let end = StructuredDate(year: 2021)
        #expect(start < end)
    }

    @Test func structuredDateJSONRoundtrip() throws {
        let date = StructuredDate(year: 2023, month: 4)
        let data = try JSONEncoder().encode(date)
        let decoded = try JSONDecoder().decode(StructuredDate.self, from: data)
        #expect(decoded.year == 2023)
        #expect(decoded.month == 4)
    }

    // MARK: NormalizedResume round-trip

    @Test func normalizedResumeJSONRoundtrip() throws {
        let resume = NormalizedResume(
            name: "Jane Doe",
            contact: ContactInfo(email: "jane@example.com"),
            summary: "Experienced engineer",
            experience: [
                NormalizedWorkEntry(
                    company: "Acme Corp",
                    title: "Engineer",
                    startDate: StructuredDate(year: 2020, month: 3),
                    endDate: nil,
                    isCurrent: true,
                    bullets: [
                        NormalizedBullet(text: "Built APIs", category: .responsibility),
                        NormalizedBullet(text: "Reduced latency 40%", category: .achievement)
                    ],
                    confidence: 0.95
                )
            ],
            education: [
                NormalizedEducationEntry(
                    institution: "State University",
                    degree: "B.Sc.",
                    field: "Computer Science",
                    startDate: StructuredDate(year: 2014, month: 9),
                    graduationDate: StructuredDate(year: 2018, month: 6)
                )
            ],
            skillCategories: [
                SkillCategory(name: "Languages", skills: ["Swift", "Python"]),
                SkillCategory(name: "Frameworks", skills: ["SwiftUI"])
            ],
            normalizerNotes: ["Start month for Acme role was inferred"]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(resume)
        let decoded = try JSONDecoder().decode(NormalizedResume.self, from: data)

        #expect(decoded.name == "Jane Doe")
        #expect(decoded.experience.count == 1)
        #expect(decoded.experience[0].isCurrent == true)
        #expect(decoded.experience[0].bullets.count == 2)
        #expect(decoded.experience[0].bullets[1].category == .achievement)
        #expect(decoded.education[0].graduationDate?.year == 2018)
        #expect(decoded.skillCategories.count == 2)
        #expect(decoded.skillCategories[0].name == "Languages")
        #expect(decoded.normalizerNotes.count == 1)
    }

    // MARK: Snake_case CodingKeys

    @Test func normalizedWorkEntryUsesSnakeCaseKeys() throws {
        let entry = NormalizedWorkEntry(
            company: "Corp",
            startDate: StructuredDate(year: 2021, month: 1),
            isCurrent: true
        )
        let data = try JSONEncoder().encode(entry)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["start_date"] != nil)
        #expect(json?["startDate"] == nil)
        #expect(json?["is_current"] != nil)
    }
}
