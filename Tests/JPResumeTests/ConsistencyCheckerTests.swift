import Testing
@testable import jpresume
import Foundation

@Suite("Resume Consistency Checker")
struct ConsistencyCheckerTests {

    // MARK: - Helpers

    private func work(
        company: String = "Corp",
        title: String? = nil,
        start: StructuredDate? = nil,
        end: StructuredDate? = nil,
        isCurrent: Bool = false,
        location: String? = nil,
        bullets: [NormalizedBullet] = []
    ) -> NormalizedWorkEntry {
        NormalizedWorkEntry(
            company: company,
            title: title,
            startDate: start,
            endDate: end,
            isCurrent: isCurrent,
            location: location,
            bullets: bullets
        )
    }

    private func makeResume(experience: [NormalizedWorkEntry]) -> NormalizedResume {
        NormalizedResume(name: "Test User", experience: experience)
    }

    // MARK: - Experience year computation

    @Test func totalSoftwareYearsFromTimeline() {
        // 2002 to 2025-ish (current role) = ~23 years
        let entries = [
            work(company: "Early Corp", start: StructuredDate(year: 2002, month: 6),
                 end: StructuredDate(year: 2010, month: 3)),
            work(company: "Mid Corp", start: StructuredDate(year: 2010, month: 4),
                 end: StructuredDate(year: 2018, month: 12)),
            work(company: "Current Corp", start: StructuredDate(year: 2019, month: 1), isCurrent: true)
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        let derived = result.derivedExperience!

        // Span from 2002/06 to now — should be 20+ years, definitely not 13
        #expect(derived.totalSoftwareYears >= 20)
        #expect(derived.totalSoftwareYears <= 25)
    }

    @Test func totalYearsNotThirteenWhenStartIs2002() {
        // This is the specific bug scenario: "13年以上" when career starts in 2002
        let entries = [
            work(company: "First", start: StructuredDate(year: 2002, month: 1),
                 end: StructuredDate(year: 2008, month: 12)),
            work(company: "Second", start: StructuredDate(year: 2009, month: 1),
                 end: StructuredDate(year: 2015, month: 6)),
            work(company: "Third", start: StructuredDate(year: 2015, month: 7), isCurrent: true)
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        let derived = result.derivedExperience!

        #expect(derived.totalSoftwareYears != 13)
        #expect(derived.totalSoftwareYears >= 20)
    }

    @Test func iosYearsComputed() {
        let entries = [
            work(company: "Web Corp", title: "Backend Developer",
                 start: StructuredDate(year: 2010, month: 1),
                 end: StructuredDate(year: 2015, month: 12)),
            work(company: "Mobile Corp", title: "iOS Developer",
                 start: StructuredDate(year: 2016, month: 1),
                 end: StructuredDate(year: 2020, month: 12)),
            work(company: "Current", title: "Senior iOS Engineer",
                 start: StructuredDate(year: 2021, month: 1), isCurrent: true)
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        let derived = result.derivedExperience!

        #expect(derived.iosYears != nil)
        #expect(derived.iosYears! >= 8)
    }

    @Test func iosYearsNilWhenNoIOSRoles() {
        let entries = [
            work(company: "Backend Inc", title: "Backend Developer",
                 start: StructuredDate(year: 2015, month: 1),
                 end: StructuredDate(year: 2020, month: 12))
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.iosYears == nil)
    }

    @Test func emptyExperienceProducesZeroYears() {
        let result = ResumeConsistencyChecker.check(makeResume(experience: []))
        #expect(result.derivedExperience?.totalSoftwareYears == 0)
    }

    // MARK: - Overlap detection and repair

    @Test func repairsOverlappingRoles() {
        // Role A ends 2020/06, Role B starts 2020/01 → overlap → repair B start to 2020/06
        let entries = [
            work(company: "A", start: StructuredDate(year: 2018, month: 1),
                 end: StructuredDate(year: 2020, month: 6)),
            work(company: "B", start: StructuredDate(year: 2020, month: 1),
                 end: StructuredDate(year: 2022, month: 12))
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))

        #expect(result.experience[1].startDate?.year == 2020)
        #expect(result.experience[1].startDate?.month == 6)
        #expect(result.repairs.contains { $0.field.contains("start_date") })
    }

    @Test func noRepairForSequentialRoles() {
        let entries = [
            work(company: "A", start: StructuredDate(year: 2018, month: 1),
                 end: StructuredDate(year: 2020, month: 6)),
            work(company: "B", start: StructuredDate(year: 2020, month: 7),
                 end: StructuredDate(year: 2022, month: 12))
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.repairs.isEmpty)
    }

    @Test func currentRoleOverlapNotRepaired() {
        // Current roles are allowed to overlap with prior roles
        let entries = [
            work(company: "Full-Time", start: StructuredDate(year: 2018, month: 1), isCurrent: true),
            work(company: "Side", start: StructuredDate(year: 2020, month: 1),
                 end: StructuredDate(year: 2022, month: 12))
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        let overlapRepairs = result.repairs.filter { $0.reason.contains("Overlap") }
        #expect(overlapRepairs.isEmpty)
    }

    // MARK: - Chronological sorting

    @Test func sortsRolesChronologically() {
        let entries = [
            work(company: "Later", start: StructuredDate(year: 2020)),
            work(company: "Earlier", start: StructuredDate(year: 2015)),
            work(company: "Middle", start: StructuredDate(year: 2018))
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.experience[0].company == "Earlier")
        #expect(result.experience[1].company == "Middle")
        #expect(result.experience[2].company == "Later")
    }

    // MARK: - isCurrent flag repair

    @Test func repairsIsCurrentWithEndDate() {
        let entries = [
            work(company: "Past", start: StructuredDate(year: 2018),
                 end: StructuredDate(year: 2020), isCurrent: true)
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(!result.experience[0].isCurrent)
        #expect(result.repairs.contains { $0.field.contains("is_current") })
    }

    @Test func repairsMiddleRoleMarkedCurrent() {
        let entries = [
            work(company: "First", start: StructuredDate(year: 2015, month: 1), isCurrent: true),
            work(company: "Second", start: StructuredDate(year: 2020, month: 1), isCurrent: true)
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        // First role should have isCurrent cleared since Second is later
        #expect(!result.experience[0].isCurrent)
        #expect(result.experience[1].isCurrent)
    }

    // MARK: - International experience detection

    @Test func detectsInternationalFromLocations() {
        let entries = [
            work(company: "JP Corp", start: StructuredDate(year: 2018),
                 location: "Tokyo, Japan"),
            work(company: "US Corp", start: StructuredDate(year: 2020),
                 location: "San Francisco, CA")
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.hasInternationalTeamExperience == true)
    }

    @Test func detectsInternationalFromBullets() {
        let bullet = NormalizedBullet(text: "Led international cross-border engineering team")
        let entries = [
            work(company: "Corp", start: StructuredDate(year: 2018), bullets: [bullet])
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.hasInternationalTeamExperience == true)
    }

    @Test func noInternationalWhenAllSameLocation() {
        let entries = [
            work(company: "A", start: StructuredDate(year: 2018), location: "Tokyo, Japan"),
            work(company: "B", start: StructuredDate(year: 2020), location: "Osaka, Japan")
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.hasInternationalTeamExperience == false)
    }

    // MARK: - JP work years

    @Test func computesJPWorkYears() {
        let entries = [
            work(company: "US Corp", start: StructuredDate(year: 2010, month: 1),
                 end: StructuredDate(year: 2015, month: 12), location: "San Francisco"),
            work(company: "JP Corp", start: StructuredDate(year: 2016, month: 1),
                 end: StructuredDate(year: 2020, month: 12), location: "Tokyo, Japan")
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.jpWorkYears != nil)
        // ~5 years in Japan
        #expect(result.derivedExperience!.jpWorkYears! >= 4)
        #expect(result.derivedExperience!.jpWorkYears! <= 6)
    }

    @Test func jpWorkYearsNilWhenNoJapanRoles() {
        let entries = [
            work(company: "US Corp", start: StructuredDate(year: 2015, month: 1),
                 end: StructuredDate(year: 2020, month: 12), location: "San Francisco")
        ]
        let result = ResumeConsistencyChecker.check(makeResume(experience: entries))
        #expect(result.derivedExperience?.jpWorkYears == nil)
    }

    // MARK: - iOS role detection

    @Test func detectsIOSRoleFromTitle() {
        let entry = work(title: "Senior iOS Engineer")
        #expect(ResumeConsistencyChecker.isIOSRole(entry))
    }

    @Test func detectsIOSRoleFromBullets() {
        let bullet = NormalizedBullet(text: "Developed SwiftUI-based features for the iPhone app")
        let entry = work(bullets: [bullet])
        #expect(ResumeConsistencyChecker.isIOSRole(entry))
    }

    @Test func nonIOSRoleNotDetected() {
        let entry = work(title: "Backend Engineer",
                         bullets: [NormalizedBullet(text: "Built REST API endpoints")])
        #expect(!ResumeConsistencyChecker.isIOSRole(entry))
    }

    // MARK: - Japan role detection

    @Test func detectsJapanRoleFromLocation() {
        let entry = work(location: "Tokyo, Japan")
        #expect(ResumeConsistencyChecker.isJapanRole(entry))
    }

    @Test func detectsJapanRoleFromJapaneseLocation() {
        let entry = work(location: "東京都")
        #expect(ResumeConsistencyChecker.isJapanRole(entry))
    }

    @Test func nonJapanRoleNotDetected() {
        let entry = work(location: "San Francisco, CA")
        #expect(!ResumeConsistencyChecker.isJapanRole(entry))
    }

    @Test func noLocationMeansNotJapanRole() {
        let entry = work()
        #expect(!ResumeConsistencyChecker.isJapanRole(entry))
    }
}
