import Testing
@testable import jpresume
import Foundation

@Suite("Markdown Renderer")
struct RendererTests {
    @Test func renderRirekisho() {
        let data = RirekishoData(
            creationDate: "2026年4月16日",
            nameKanji: "田中太郎",
            nameFurigana: "タナカタロウ",
            dateOfBirth: "1990年1月1日",
            postalCode: "100-0001",
            address: "東京都千代田区千代田1-1",
            phone: "090-1234-5678",
            email: "tanaka@example.com",
            educationHistory: [
                DateDescription("2010年4月", "東京大学 工学部 入学"),
                DateDescription("2014年3月", "東京大学 工学部 卒業"),
            ],
            workHistory: [
                DateDescription("2014年4月", "株式会社ABC 入社"),
                DateDescription("", "現在に至る"),
            ],
            licenses: [
                DateDescription("2020年3月", "基本情報技術者"),
            ],
            motivation: "貴社の技術力に魅力を感じ、志望いたしました。",
            spouse: false,
            dependents: 0
        )

        let md = MarkdownRenderer.renderRirekisho(data)

        #expect(md.contains("履歴書"))
        #expect(md.contains("田中太郎"))
        #expect(md.contains("タナカタロウ"))
        #expect(md.contains("東京大学 工学部 入学"))
        #expect(md.contains("株式会社ABC 入社"))
        #expect(md.contains("現在に至る"))
        #expect(md.contains("以上"))
        #expect(md.contains("志望動機"))
        #expect(md.contains("090-1234-5678"))
    }

    @Test func renderShokumukeirekisho() {
        let data = ShokumukeirekishoData(
            creationDate: "2026年4月16日",
            name: "田中太郎",
            careerSummary: "10年の経験を有するエンジニアです。",
            workDetails: [
                CompanyDetail(
                    companyName: "株式会社ABC",
                    period: "2014年4月〜現在",
                    industry: "IT",
                    role: "シニアエンジニア",
                    responsibilities: ["システム設計", "チームリード"],
                    achievements: ["売上20%向上に貢献"]
                ),
            ],
            technicalSkills: [
                "言語": ["Python", "Go", "JavaScript"],
                "インフラ": ["AWS", "Docker"],
            ],
            selfPr: "技術力とリーダーシップを活かし貢献します。"
        )

        let md = MarkdownRenderer.renderShokumukeirekisho(data)

        #expect(md.contains("職務経歴書"))
        #expect(md.contains("職務要約"))
        #expect(md.contains("株式会社ABC"))
        #expect(md.contains("シニアエンジニア"))
        #expect(md.contains("システム設計"))
        #expect(md.contains("売上20%向上"))
        #expect(md.contains("Python"))
        #expect(md.contains("自己PR"))
    }

    @Test func skillCategoriesRenderInTaxonomyOrder() {
        let data = ShokumukeirekishoData(
            creationDate: "2026年9月14日", name: "テスト", careerSummary: "要約", workDetails: [],
            technicalSkills: [
                "その他": ["SQLite"], "AI関連": ["LLM"], "言語": ["Swift"],
                "品質・改善": ["CI/CD"], "フレームワーク": ["SwiftUI"], "設計・開発": ["API設計"],
                "資格": ["N3"]
            ],
            selfPr: nil
        )
        #expect(data.orderedTechnicalSkills.map(\.category)
                == ["言語", "フレームワーク", "設計・開発", "品質・改善", "AI関連", "その他", "資格"])

        let md = MarkdownRenderer.renderShokumukeirekisho(data)
        let positions = ["言語", "フレームワーク", "AI関連", "その他"].compactMap { md.range(of: "| \($0) |")?.lowerBound }
        #expect(positions.count == 4)
        #expect(positions == positions.sorted())
    }

}
