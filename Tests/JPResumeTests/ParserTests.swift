import Testing
@testable import jpresume
import Foundation

@Suite("Markdown Parser")
struct ParserTests {
    let sampleResume: String
    let plainTextResume: String

    init() throws {
        let url = Bundle.module.url(forResource: "sample_resume", withExtension: "md", subdirectory: "Fixtures")!
        sampleResume = try String(contentsOf: url, encoding: .utf8)
        plainTextResume = """
        KRISTOPHER BAKER
        Senior Software Engineer
        Tokyo, Japan | kristopher.g.baker@gmail.com | linkedin.com/in/kristophergbaker

        SUMMARY
        Product-focused engineer specializing in growth, consumer applications, and AI-enabled systems.

        CORE COMPETENCIES
        Languages & Platforms: Swift, Objective-C, Python; UIKit, SwiftUI, AppKit, AVFoundation
        AI-Enabled Product Development: LLM integration, RAG systems

        EXPERIENCE
        Wolt / DoorDash | Senior Software Engineer
        May 2023 – Present | Tokyo, Japan
        Lead engineer for membership growth in a large-scale consumer application.
        • Led implementation of subscription funnel improvements
        • Designed telemetry instrumentation and backend-driven UI systems

        SmartNews | Senior Software Engineer, iOS
        April 2019 – May 2023 | Tokyo, Japan
        Core iOS engineer on a consumer news application.
        • Built and shipped features across feed rendering and onboarding
        • Conducted 100+ technical interviews across engineering roles.

        EDUCATION
        University of Illinois Springfield
        Bachelor of Science, Computer Science | Minor: Mathematics
        Summa Cum Laude
        """
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

    @Test func parsePlainTextResume() {
        let preprocessed = ResumeTextPreprocessor.preprocess(plainTextResume, sourceKind: .pdf)
        let resume = PlainTextResumeParser.parse(preprocessed.cleanedText)
        #expect(resume.name == "KRISTOPHER BAKER")
        #expect(resume.contact.email == "kristopher.g.baker@gmail.com")
        #expect(resume.experience.count == 2)
        #expect(resume.experience[0].company == "Wolt / DoorDash")
        #expect(resume.experience[0].startDate == "May 2023")
        #expect(resume.experience[0].endDate == "Present")
        #expect(resume.experience[0].location == "Tokyo, Japan")
        #expect(resume.experience[0].bullets.count == 3)
        #expect(resume.experience[0].bullets.first == "Lead engineer for membership growth in a large-scale consumer application.")
        #expect(resume.education.count == 1)
        #expect(resume.education[0].institution == "University of Illinois Springfield")
        #expect(resume.skills.contains("LLM integration, RAG systems") == false)
        #expect(resume.skills.contains("LLM integration"))
        #expect(resume.skills.contains("Swift"))
        #expect(resume.skills.contains("Python"))
    }

    @Test func preprocessorFixesCommonOCRTechTerms() {
        let text = """
        SUMMARY
        Building Al-enabled features with SwiftUl and OpenAl.
        Authored RFs and stored vectors in 5Qlite.
        """
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: .pdf)
        #expect(preprocessed.cleanedText.contains("AI-enabled"))
        #expect(preprocessed.cleanedText.contains("SwiftUI"))
        #expect(preprocessed.cleanedText.contains("OpenAI"))
        #expect(preprocessed.cleanedText.contains("RFCs"))
        #expect(preprocessed.cleanedText.contains("SQLite"))
    }
}
