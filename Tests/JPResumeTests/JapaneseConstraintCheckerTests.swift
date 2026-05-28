import Testing
@testable import jpresume

@Suite("Japanese Constraint Checker")
struct JapaneseConstraintCheckerTests {

    // MARK: - Rirekisho

    @Test func cleanRirekishoHasNoViolations() {
        let data = makeRirekisho(
            workHistory: [
                DateDescription("令和元年4月", "株式会社サンプル 入社"),
                DateDescription("", "現在に至る")
            ],
            motivation: "貴社の事業に貢献してまいりたく、応募いたしました。"
        )
        #expect(JapaneseConstraintChecker.check(data).isEmpty)
    }

    @Test func detectsCurrentInDateColumn() {
        let data = makeRirekisho(
            workHistory: [
                DateDescription("令和元年4月", "株式会社サンプル 入社"),
                DateDescription("現在", "株式会社サンプル 現在に至る")
            ]
        )
        let violations = JapaneseConstraintChecker.check(data)
        #expect(violations.contains { $0.rule == "rirekisho.current_row_has_date" })
    }

    @Test func detectsMissingContinuationRow() {
        let data = makeRirekisho(
            workHistory: [
                DateDescription("令和元年4月", "株式会社サンプル 入社")
                // Should have a 「現在に至る」row but doesn't.
            ]
        )
        let violations = JapaneseConstraintChecker.check(data)
        #expect(violations.contains { $0.rule == "rirekisho.missing_continuation_row" })
    }

    @Test func detectsForbiddenPhrases() {
        let data = makeRirekisho(
            motivation: "即戦力として貢献できることを確信しております。"
        )
        let violations = JapaneseConstraintChecker.check(data)
        let rules = Set(violations.map(\.rule))
        #expect(rules.contains("rirekisho.forbidden_phrase"))
        #expect(violations.count >= 2)  // 即戦力として貢献 + 確信して
    }

    // MARK: - Shokumukeirekisho

    @Test func cleanShokumuHasNoViolations() {
        let data = makeShokumu(
            careerSummary: "iOSアプリ開発を中心にキャリアを積んでまいりました。" +
                           "消費者向けプロダクトの設計から運用まで一貫して担当しております。",
            selfPr: "チームを横断した合意形成を得意としており、複数の関係部門と連携した経験がございます。" +
                    "後進のメンタリングにも継続的に取り組んでまいりました。"
        )
        #expect(JapaneseConstraintChecker.check(data).isEmpty)
    }

    @Test func detectsDuplicateOpeningSentence() {
        let data = makeShokumu(
            careerSummary: "これまでiOSアプリ開発に従事してまいりました。詳細省略。",
            selfPr: "これまでiOSアプリ開発に従事してまいりました。詳細省略。"
        )
        let violations = JapaneseConstraintChecker.check(data)
        let rules = Set(violations.map(\.rule))
        #expect(rules.contains("shokumu.duplicate_opening"))
    }

    @Test func detectsBothOpeningWithYearCount() {
        let data = makeShokumu(
            careerSummary: "13年以上にわたりiOS開発に従事してまいりました。",
            selfPr: "10年以上にわたりチーム横断のプロジェクトに参画してまいりました。"
        )
        let violations = JapaneseConstraintChecker.check(data)
        #expect(violations.contains { $0.rule == "shokumu.duplicate_year_count_opening" })
    }

    @Test func detectsMetricDuplicatedAcrossSections() {
        let data = makeShokumu(
            careerSummary: "新規会員登録数の29.8%増加に寄与いたしました。詳細省略。",
            selfPr: "前述の29.8%向上に加え、横断的な改善も推進しております。"
        )
        let violations = JapaneseConstraintChecker.check(data)
        #expect(violations.contains { $0.rule == "shokumu.metric_duplicated" })
    }

    @Test func ignoresSingleMetricInOneSection() {
        let data = makeShokumu(
            careerSummary: "新規会員登録数の29.8%増加に寄与いたしました。詳細省略。",
            selfPr: "関係部門との合意形成を主導してまいりました。詳細省略。"
        )
        let violations = JapaneseConstraintChecker.check(data)
        #expect(!violations.contains { $0.rule == "shokumu.metric_duplicated" })
    }

    // MARK: - Helpers

    private func makeRirekisho(
        workHistory: [DateDescription] = [],
        motivation: String? = nil
    ) -> RirekishoData {
        RirekishoData(
            creationDate: "令和7年5月",
            nameKanji: "山田 太郎",
            nameFurigana: "ヤマダ タロウ",
            dateOfBirth: "平成元年1月1日",
            gender: nil, postalCode: nil, address: nil, addressFurigana: nil,
            contactPostalCode: nil, contactAddress: nil, contactAddressFurigana: nil,
            phone: nil, email: nil, photoPath: nil,
            educationHistory: [],
            workHistory: workHistory,
            licenses: [],
            motivation: motivation,
            hobbies: nil, commuteTime: nil, spouse: nil, dependents: nil, dependentsExclSpouse: nil
        )
    }

    private func makeShokumu(careerSummary: String, selfPr: String?) -> ShokumukeirekishoData {
        ShokumukeirekishoData(
            creationDate: "令和7年5月", name: "山田 太郎",
            careerSummary: careerSummary, workDetails: [],
            technicalSkills: [:], selfPr: selfPr
        )
    }
}
