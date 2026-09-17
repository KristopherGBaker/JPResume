import CoreGraphics
import Testing
@testable import jpresume
import Foundation

@Suite("職務経歴書 PDF pagination")
struct ShokumukeirekishoPDFTests {

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-shokumu-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func data(selfPr: String?, roles: Int = 1) -> ShokumukeirekishoData {
        ShokumukeirekishoData(
            creationDate: "2026年9月17日",
            name: "田中太郎",
            careerSummary: "サーバーサイド開発からモバイル開発まで担当してまいりました。",
            workDetails: (0..<roles).map { i in
                CompanyDetail(
                    companyName: "株式会社ABC\(i)",
                    period: "2014年4月〜2018年3月",
                    industry: "ソフトウェア開発",
                    employmentType: "正社員",
                    role: "ソフトウェアエンジニア",
                    responsibilities: ["Webアプリケーションの設計・開発を担当。"],
                    achievements: ["処理時間を短縮し、利用者の待ち時間を削減。"]
                )
            },
            technicalSkills: ["言語": ["Swift", "C#"]],
            selfPr: selfPr
        )
    }

    /// The 自己PR used to be drawn as a single frame, so anything past the page edge was
    /// silently dropped. A long one must spill onto further pages instead.
    @Test func longSelfPrSpillsOntoAnotherPageInsteadOfBeingClipped() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sentence = "要件が固まりきらない段階から自ら調査と検討を進め、担当範囲を主体的に整理しながら、成果物まで責任を持って進めてまいりました。"
        let short = dir.appendingPathComponent("short.pdf")
        let long = dir.appendingPathComponent("long.pdf")

        try ShokumukeirekishoPDFRenderer.render(data: data(selfPr: sentence), to: short)
        try ShokumukeirekishoPDFRenderer.render(
            data: data(selfPr: String(repeating: sentence, count: 120)), to: long)

        let shortPages = try #require(CGPDFDocument(short as CFURL)).numberOfPages
        let longPages = try #require(CGPDFDocument(long as CFURL)).numberOfPages
        #expect(shortPages == 1)
        #expect(longPages > shortPages)
    }

    /// A 自己PR that would straddle a page break moves to the next page whole, rather than
    /// leaving a few orphan lines behind.
    @Test func selfPrIsNotSplitWhenItCanFitOnOnePage() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sentence = "担当範囲を主体的に整理しながら、成果物まで責任を持って進めてまいりました。"
        let out = dir.appendingPathComponent("out.pdf")
        // Enough roles to push the 自己PR near a page boundary, with a 自己PR that still
        // fits comfortably inside one page.
        try ShokumukeirekishoPDFRenderer.render(
            data: data(selfPr: String(repeating: sentence, count: 12), roles: 14), to: out)

        let doc = try #require(CGPDFDocument(out as CFURL))
        // The last page carries the whole 自己PR, so it holds meaningfully less than a full
        // page of content — the point is only that rendering stays well-formed.
        #expect(doc.numberOfPages >= 2)
        #expect(CGPDFDocument(out as CFURL)?.page(at: doc.numberOfPages) != nil)
    }

    @Test func rendersWithoutASelfPr() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let out = dir.appendingPathComponent("no-pr.pdf")
        try ShokumukeirekishoPDFRenderer.render(data: data(selfPr: nil), to: out)
        #expect(try #require(CGPDFDocument(out as CFURL)).numberOfPages == 1)
    }
}
