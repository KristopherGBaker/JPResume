import Testing
@testable import jpresume
import Foundation

@Suite("Japanese Polish Rules")
struct JapanesePolishTests {

    // MARK: - Experience year replacement

    @Test func replacesGenericExperienceYears() {
        let derived = DerivedExperience(totalSoftwareYears: 22)
        let input = "13年以上のソフトウェア開発経験を持つエンジニアです。"
        let result = JapanesePolishRules.replaceExperienceYears(input, derived: derived)
        #expect(result.contains("22年以上の"))
        #expect(!result.contains("13年以上の"))
    }

    @Test func replacesApproximateExperienceYears() {
        let derived = DerivedExperience(totalSoftwareYears: 22)
        let input = "約13年の開発経験があります。"
        let result = JapanesePolishRules.replaceExperienceYears(input, derived: derived)
        #expect(result.contains("22年以上の"))
        #expect(!result.contains("約13年の"))
    }

    @Test func replacesIOSExperienceYears() {
        let derived = DerivedExperience(totalSoftwareYears: 22, iosYears: 10)
        let input = "5年以上のiOS開発経験"
        let result = JapanesePolishRules.replaceExperienceYears(input, derived: derived)
        #expect(result.contains("10年以上のiOS開発経験"))
        #expect(!result.contains("5年以上の"))
    }

    @Test func leavesTextAloneWhenNoMatchingPattern() {
        let derived = DerivedExperience(totalSoftwareYears: 22)
        let input = "チームリーダーとしてプロジェクトを推進しました。"
        let result = JapanesePolishRules.replaceExperienceYears(input, derived: derived)
        #expect(result == input)
    }

    // MARK: - Japanese phrase normalization

    @Test func normalizesJLPTCertification() {
        let input = "日本語能力試験 N3 取得"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result == "日本語能力試験N3合格")
    }

    @Test func normalizesDRIPhrase() {
        let input = "フロントエンドDRI（直接責任者）として開発を主導"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result.contains("iOS開発の主担当"))
        #expect(!result.contains("DRI"))
    }

    @Test func normalizesCrossTeamPhrase() {
        let input = "クロスチームでの協業を推進"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result.contains("複数チーム横断"))
        #expect(!result.contains("クロスチーム"))
    }

    @Test func normalizesBackendDrivenUI() {
        let input = "バックエンド駆動型UIの設計と実装"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result.contains("サーバー駆動型UI"))
        #expect(!result.contains("バックエンド駆動型UI"))
    }

    @Test func normalizesSubscriberPhrase() {
        let input = "追加購読者の獲得に貢献"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result.contains("増分会員登録"))
    }

    @Test func normalizesCrossFunctional() {
        let input = "クロスファンクショナルチームでの開発"
        let result = JapanesePolishRules.normalizeJapanesePhrases(input)
        #expect(result.contains("職種横断チーム"))
    }

    // MARK: - Certification normalization

    @Test func normalizesJLPTVariants() {
        #expect(JapanesePolishRules.normalizeCertification("JLPT N2") == "日本語能力試験N2合格")
        #expect(JapanesePolishRules.normalizeCertification("JLPT N3取得") == "日本語能力試験N3合格")
        #expect(JapanesePolishRules.normalizeCertification("日本語能力試験N1 取得") == "日本語能力試験N1合格")
    }

    @Test func leavesNonJLPTCertificationsAlone() {
        let input = "AWS認定 ソリューションアーキテクト"
        #expect(JapanesePolishRules.normalizeCertification(input) == input)
    }

    // MARK: - Company name normalization

    @Test func removesIncWhenKabushikiPresent() {
        let input = "株式会社Example, Inc."
        let result = JapanesePolishRules.normalizeCompanyName(input)
        #expect(result == "株式会社Example")
        #expect(!result.contains("Inc"))
    }

    @Test func keepsIncWhenNoKabushiki() {
        let input = "Example, Inc."
        let result = JapanesePolishRules.normalizeCompanyName(input)
        #expect(result == "Example, Inc.")
    }

    @Test func removesLLCWhenGoudouPresent() {
        let input = "合同会社Example, LLC"
        let result = JapanesePolishRules.normalizeCompanyName(input)
        #expect(result == "合同会社Example")
    }

    // MARK: - Section deduplication

    @Test func removesDuplicateLeadSentence() {
        let data = ShokumukeirekishoData(
            creationDate: "2025年4月16日",
            name: "テスト太郎",
            careerSummary: "20年以上のソフトウェア開発経験を有するエンジニアです。iOS開発を専門としています。",
            workDetails: [],
            technicalSkills: [:],
            selfPr: "20年以上のソフトウェア開発経験を有するエンジニアです。リーダーシップとメンタリングに注力しています。"
        )
        let result = JapanesePolishRules.deduplicateSections(data)
        // selfPr should not start with the same sentence as careerSummary
        #expect(result.selfPr != nil)
        #expect(!result.selfPr!.hasPrefix("20年以上の"))
        #expect(result.selfPr!.contains("リーダーシップ"))
    }

    @Test func doesNotRemoveWhenSentencesDiffer() {
        let data = ShokumukeirekishoData(
            creationDate: "2025年4月16日",
            name: "テスト太郎",
            careerSummary: "技術力の高いエンジニアです。",
            workDetails: [],
            technicalSkills: [:],
            selfPr: "リーダーシップとチームワークを重視しています。"
        )
        let result = JapanesePolishRules.deduplicateSections(data)
        #expect(result.selfPr == data.selfPr)
    }

    @Test func doesNotEmptySelfPrOnDedup() {
        let data = ShokumukeirekishoData(
            creationDate: "2025年4月16日",
            name: "テスト太郎",
            careerSummary: "経験豊富なエンジニアです。",
            workDetails: [],
            technicalSkills: [:],
            selfPr: "経験豊富なエンジニアです。"
        )
        let result = JapanesePolishRules.deduplicateSections(data)
        // Should not empty the selfPr — leave as-is if removing would empty it
        #expect(result.selfPr != nil)
        #expect(!result.selfPr!.isEmpty)
    }

    // MARK: - Sentence extraction

    @Test func extractsSentences() {
        let text = "一つ目の文です。二つ目の文です。三つ目"
        let sentences = JapanesePolishRules.extractSentences(text)
        #expect(sentences.count == 3)
        #expect(sentences[0] == "一つ目の文です。")
        #expect(sentences[1] == "二つ目の文です。")
        #expect(sentences[2] == "三つ目")
    }

    // MARK: - Full polish integration

    @Test func polishShokumukeirekishoFixesExperienceYears() {
        let data = ShokumukeirekishoData(
            creationDate: "2025年4月16日",
            name: "テスト太郎",
            careerSummary: "13年以上のソフトウェア開発経験を持つエンジニア。",
            workDetails: [
                CompanyDetail(
                    companyName: "株式会社Example, Inc.",
                    period: "2020年〜現在",
                    responsibilities: ["バックエンド駆動型UIの設計"],
                    achievements: ["クロスチームでの協業を推進"]
                )
            ],
            technicalSkills: ["資格": ["JLPT N2"]],
            selfPr: "追加購読者の獲得に貢献しました。"
        )
        let derived = DerivedExperience(totalSoftwareYears: 22, iosYears: 10)
        let result = JapanesePolishRules.polish(data, derived: derived)

        // Experience years fixed
        #expect(result.careerSummary.contains("22年以上の"))
        #expect(!result.careerSummary.contains("13年以上の"))

        // Company name cleaned
        #expect(result.workDetails[0].companyName == "株式会社Example")

        // Phrases normalized
        #expect(result.workDetails[0].responsibilities[0].contains("サーバー駆動型UI"))
        #expect(result.workDetails[0].achievements[0].contains("複数チーム横断"))

        // Certifications normalized
        #expect(result.technicalSkills["資格"]?[0] == "日本語能力試験N2合格")

        // Self-PR normalized
        #expect(result.selfPr!.contains("増分会員登録"))
    }

    @Test func polishRirekishoFixesCertifications() {
        let data = RirekishoData(
            creationDate: "2025年4月16日",
            nameKanji: "テスト太郎",
            nameFurigana: "テストタロウ",
            dateOfBirth: "1990年1月1日",
            educationHistory: [],
            workHistory: [DateDescription("2020年4月", "株式会社Example, Inc. 入社")],
            licenses: [DateDescription("2020年3月", "日本語能力試験 N3 取得")]
        )
        let result = JapanesePolishRules.polish(data, derived: nil)

        // License normalized
        #expect(result.licenses[0].description == "日本語能力試験N3合格")

        // Company name normalized in work history
        #expect(result.workHistory[0].description.contains("株式会社Example"))
        #expect(!result.workHistory[0].description.contains("Inc."))
    }

    // MARK: - Side project inclusion toggle (via GenerationOptions)

    @Test func generationOptionsDefaultExcludesSideProjects() {
        let options = GenerationOptions()
        #expect(!options.includeSideProjects)
        #expect(options.includeOlderIrrelevantRoles)
    }

    @Test func generationOptionsCanIncludeSideProjects() {
        let options = GenerationOptions(includeSideProjects: true)
        #expect(options.includeSideProjects)
    }

    @Test func generationOptionsCanExcludeOlderRoles() {
        let options = GenerationOptions(includeOlderIrrelevantRoles: false)
        #expect(!options.includeOlderIrrelevantRoles)
    }
}
