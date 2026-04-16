import Testing
@testable import jpresume
import Foundation

@Suite("Markdown Parser")
struct ParserTests {
    let sampleResume: String

    init() throws {
        let url = Bundle.module.url(forResource: "sample_resume", withExtension: "md", subdirectory: "Fixtures")!
        sampleResume = try String(contentsOf: url, encoding: .utf8)
    }

    @Test func parseName() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.name == "Jane Doe")
    }

    @Test func parseContact() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.contact.email == "jane@example.com")
        #expect(resume.contact.phone == "+81-80-9999-0000")
    }

    @Test func parseSummary() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.summary?.contains("Full-stack developer") == true)
    }

    @Test func parseExperience() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.experience.count == 2)
        #expect(resume.experience[0].company == "Google")
        #expect(resume.experience[0].title == "Software Engineer")
        #expect(resume.experience[0].startDate == "Apr 2020")
        #expect(resume.experience[0].endDate == "Present")
        #expect(resume.experience[0].bullets.count == 2)
        #expect(resume.experience[1].company == "Startup Co")
    }

    @Test func parseEducation() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.education.count == 2)
        #expect(resume.education[0].institution == "MIT")
        #expect(resume.education[0].degree == "M.S. Computer Science")
        #expect(resume.education[1].institution == "Tokyo University")
    }

    @Test func parseSkills() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.skills.contains("Python"))
        #expect(resume.skills.contains("Go"))
        #expect(resume.skills.contains("Docker"))
        #expect(resume.skills.count == 7)
    }

    @Test func parseCertifications() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.certifications.count == 1)
        #expect(resume.certifications[0].contains("AWS"))
    }

    @Test func parseLanguages() {
        let resume = MarkdownParser.parse(sampleResume)
        #expect(resume.languages.count == 2)
        #expect(resume.languages.contains(where: { $0.contains("English") }))
        #expect(resume.languages.contains(where: { $0.contains("Japanese") }))
    }

    @Test func parseEmptyResume() {
        let resume = MarkdownParser.parse("")
        #expect(resume.name == nil)
        #expect(resume.experience.isEmpty)
    }

    @Test func parseMinimalResume() {
        let text = "# John\n\n## Experience\n\n### Acme | Dev | 2020 - 2021\n\n- Did things\n"
        let resume = MarkdownParser.parse(text)
        #expect(resume.name == "John")
        #expect(resume.experience.count == 1)
        #expect(resume.experience[0].company == "Acme")
    }
}
