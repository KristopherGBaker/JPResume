import DocPipeline
import Testing
@testable import jpresume
import Foundation
import Shikisha

/// Drives ResumeAI and Stages through Shikisha's FakeChatModel so the critique loop,
/// naming context, and validation feedback loop can be tested without API calls.
@Suite("Orchestration (critique, naming, feedback)")
struct OrchestrationTests {

    // MARK: - Critique loop

    @Test func critiqueLoopSkippedWhenInitialIsClean() async throws {
        let clean = makeRirekishoClean()
        let model = FakeChatModel(responses: [aiMessage(clean)])

        let result = try await ResumeAI(model: model, verbose: false)
            .generateRirekisho(normalized: NormalizedResume(name: "X"),
                               config: JapanConfig(), era: .western)

        #expect(result.critiquePasses == 0)
        #expect(result.remainingViolations.isEmpty)
        let calls = await model.snapshotInvocations()
        #expect(calls.count == 1)  // no critique call needed
    }

    @Test func critiqueLoopClearsViolationsAfterOnePass() async throws {
        let dirty = makeRirekishoDirty()      // has forbidden phrase in motivation
        let clean = makeRirekishoClean()
        let model = FakeChatModel(responses: [aiMessage(dirty), aiMessage(clean)])

        let result = try await ResumeAI(model: model, verbose: false)
            .generateRirekisho(normalized: NormalizedResume(name: "X"),
                               config: JapanConfig(), era: .western)

        #expect(result.critiquePasses == 1)
        #expect(result.remainingViolations.isEmpty)
        let calls = await model.snapshotInvocations()
        #expect(calls.count == 2)  // initial + 1 critique
    }

    @Test func critiqueLoopExhaustsMaxAndSurfacesRemaining() async throws {
        let dirty = makeRirekishoDirty()
        // 4 dirty responses: initial + 3 critique attempts, all dirty.
        let model = FakeChatModel(
            responses: Array(repeating: aiMessage(dirty), count: 4)
        )

        let result = try await ResumeAI(model: model, verbose: false, maxCritiquePasses: 3)
            .generateRirekisho(normalized: NormalizedResume(name: "X"),
                               config: JapanConfig(), era: .western)

        #expect(result.critiquePasses == 3)
        #expect(!result.remainingViolations.isEmpty)
        let calls = await model.snapshotInvocations()
        #expect(calls.count == 4)
    }

    @Test func critiquePassesNamingContextToShokumuPrompt() async throws {
        let clean = makeShokumuClean()
        let model = FakeChatModel(responses: [aiMessage(clean)])
        let naming = NamingContext(candidateName: "山田 太郎",
                                    companyNames: ["株式会社サンプル", "テック株式会社"])

        _ = try await ResumeAI(model: model, verbose: false)
            .generateShokumukeirekisho(normalized: NormalizedResume(name: "X"),
                                       config: JapanConfig(), era: .western,
                                       namingContext: naming)

        let calls = await model.snapshotInvocations()
        let systemMessage = calls.first?.first?.content ?? ""
        #expect(systemMessage.contains("株式会社サンプル"))
        #expect(systemMessage.contains("テック株式会社"))
        #expect(systemMessage.contains("山田 太郎"))
    }

    // MARK: - NamingContext extraction

    @Test func namingContextExtractsCompaniesFromWorkHistory() {
        let data = makeRirekishoClean()
        let ctx = NamingContext.from(data)
        #expect(ctx.candidateName == "山田 太郎")
        #expect(ctx.companyNames == ["株式会社サンプル"])
    }

    @Test func namingContextSkipsContinuationRow() {
        let data = RirekishoData(
            creationDate: "令和7年5月", nameKanji: "佐藤 花子", nameFurigana: "サトウ ハナコ",
            dateOfBirth: "平成元年1月1日",
            gender: nil, postalCode: nil, address: nil, addressFurigana: nil,
            contactPostalCode: nil, contactAddress: nil, contactAddressFurigana: nil,
            phone: nil, email: nil, photoPath: nil,
            educationHistory: [],
            workHistory: [
                DateDescription("令和元年4月", "株式会社A 入社"),
                DateDescription("令和3年12月", "株式会社A 退職"),
                DateDescription("令和4年1月", "株式会社B 入社"),
                DateDescription("", "現在に至る")
            ],
            licenses: [], motivation: nil, hobbies: nil, commuteTime: nil,
            spouse: nil, dependents: nil, dependentsExclSpouse: nil
        )
        let ctx = NamingContext.from(data)
        #expect(ctx.companyNames == ["株式会社A", "株式会社B"])
    }

    // MARK: - Validation feedback loop

    @Test func feedbackLoopAcceptsRefinementWhenIssuesDecrease() async throws {
        let dirtyNormalized = NormalizedResume(name: nil)         // 3 issues: name, experience, education
        let refinedNormalized = NormalizedResume(name: "Refined") // 2 issues: experience, education
        let model = FakeChatModel(responses: [
            aiMessage(dirtyNormalized),
            aiMessage(refinedNormalized)
        ])

        let result = try await Stages.normalize(
            western: WesternResume(name: nil), inputs: makeInputs(), config: JapanConfig(),
            model: model, verbose: false, maxRefinements: 1
        )

        #expect(result.name == "Refined")
        let calls = await model.snapshotInvocations()
        #expect(calls.count == 2)  // initial + 1 refinement
    }

    @Test func feedbackLoopRevertsWhenRefinementDoesNotImprove() async throws {
        let dirty = NormalizedResume(name: nil)  // 3 issues
        // Refinement returns the same shape — 3 issues, no improvement.
        let model = FakeChatModel(responses: [aiMessage(dirty), aiMessage(dirty)])

        let result = try await Stages.normalize(
            western: WesternResume(name: nil), inputs: makeInputs(), config: JapanConfig(),
            model: model, verbose: false, maxRefinements: 2
        )

        #expect(result.name == nil)
        let calls = await model.snapshotInvocations()
        // Initial + 1 refinement attempt that didn't improve — loop bails after the no-improvement check.
        #expect(calls.count == 2)
    }

    @Test func feedbackLoopSkipsWhenMaxRefinementsZero() async throws {
        let dirty = NormalizedResume(name: nil)
        let model = FakeChatModel(responses: [aiMessage(dirty)])

        _ = try await Stages.normalize(
            western: WesternResume(name: nil), inputs: makeInputs(), config: JapanConfig(),
            model: model, verbose: false, maxRefinements: 0
        )

        let calls = await model.snapshotInvocations()
        #expect(calls.count == 1)
    }

    @Test func feedbackLoopSkipsWhenInitialIsClean() async throws {
        let clean = NormalizedResume(
            name: "Clean Resume",
            experience: [NormalizedWorkEntry(company: "Co", startDate: StructuredDate(year: 2020))],
            education: [NormalizedEducationEntry(institution: "Uni")]
        )
        let model = FakeChatModel(responses: [aiMessage(clean)])

        _ = try await Stages.normalize(
            western: WesternResume(name: "Clean Resume"), inputs: makeInputs(), config: JapanConfig(),
            model: model, verbose: false, maxRefinements: 2
        )

        let calls = await model.snapshotInvocations()
        #expect(calls.count == 1)
    }

    // MARK: - Fixtures

    private func makeRirekishoClean() -> RirekishoData {
        RirekishoData(
            creationDate: "令和7年5月", nameKanji: "山田 太郎", nameFurigana: "ヤマダ タロウ",
            dateOfBirth: "平成元年1月1日",
            gender: nil, postalCode: nil, address: nil, addressFurigana: nil,
            contactPostalCode: nil, contactAddress: nil, contactAddressFurigana: nil,
            phone: nil, email: nil, photoPath: nil,
            educationHistory: [],
            workHistory: [
                DateDescription("令和元年4月", "株式会社サンプル 入社"),
                DateDescription("", "現在に至る")
            ],
            licenses: [],
            motivation: "貴社の事業に関心があり、応募いたしました。",
            hobbies: nil, commuteTime: nil, spouse: nil, dependents: nil, dependentsExclSpouse: nil
        )
    }

    private func makeRirekishoDirty() -> RirekishoData {
        var data = makeRirekishoClean()
        data.motivation = "即戦力として貢献できることを確信しております。"
        return data
    }

    private func makeShokumuClean() -> ShokumukeirekishoData {
        ShokumukeirekishoData(
            creationDate: "令和7年5月", name: "山田 太郎",
            careerSummary: "iOSアプリ開発を中心にキャリアを積んでまいりました。詳細省略。",
            workDetails: [],
            technicalSkills: [:],
            selfPr: "横断的な連携を得意としております。詳細省略。"
        )
    }

    private func makeInputs() -> InputsData {
        InputsData(sourcePath: "/tmp/r.md", markdownHash: "h", config: JapanConfig(),
                   sourceKind: .markdown, sourceText: "x", cleanedText: "x")
    }

    /// Encode a Codable as the AIMessage content the FakeChatModel will return.
    private func aiMessage<T: Encodable>(_ value: T) -> AIMessage {
        let data = try! JSONEncoder().encode(value)  // swiftlint:disable:this force_try
        return AIMessage(content: String(data: data, encoding: .utf8)!)
    }
}
