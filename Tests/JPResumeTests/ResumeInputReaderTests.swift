import AppKit
import CoreText
import Foundation
import PDFKit
import Testing
@testable import jpresume

@Suite("Resume Input Reader")
struct ResumeInputReaderTests {

    // Content long enough to exceed the 100-char text-layer threshold
    private let richContent = "Jane Doe\nSoftware Engineer\njane@example.com\n"
        + String(repeating: "Built scalable systems using Swift and Go. ", count: 4)

    // Short content used to test the OCR fallback path (below 100-char threshold)
    private let shortContent = "Jane Doe\nSoftware Engineer"

    // Genericized resume-shaped content based on the same kind of two-page PDF layout
    // we care about in production, without using any real personal information.
    private let parsedResumeContent = """
    JORDAN EXAMPLE
    Senior Software Engineer
    Tokyo, Japan | jordan@example.com | linkedin.com/in/jordanexample
    SUMMARY
    Software engineer building consumer products and AI-enabled applications.
    CORE COMPETENCIES
    Product & Growth Engineering: Subscription systems, A/B testing
    AI-Enabled Product Development: LLM integration (Anthropic, OpenAI, OpenRouter, Ollama), RAG systems
    Languages & Platforms: Swift, Objective-C, Python; UIKit, SwiftUI, AppKit, AVFoundation
    EXPERIENCE
    Northstar / Atlas | Senior Software Engineer
    May 2023 – Present | Tokyo, Japan
    ●
    Designed telemetry instrumentation and backend-driven UI systems.
    Beacon News | Senior Software Engineer, iOS
    April 2019 – May 2023 | Tokyo, Japan
    ●
    Built and shipped onboarding and navigation features.
    Summit Fit | Software Engineer, iOS
    March 2013 – July 2018 | Boise, Idaho
    ●
    Implemented CI/CD pipelines and release automation.
    Projects
    Aside | AI Mock Interview Coach (macOS) | Personal project (in progress)
    Building a native macOS application for AI-driven mock interviews.
    ●
    Designed a provider-agnostic LLM orchestration layer supporting Anthropic, OpenAI, OpenRouter, and local models (Ollama)
    EDUCATION
    Western State University
    Bachelor of Science, Computer Science | Minor: Mathematics
    Summa Cum Laude
    """

    // MARK: - Markdown

    @Test func readsMarkdownFile() async throws {
        let url = Bundle.module.url(forResource: "sample_resume", withExtension: "md", subdirectory: "Fixtures")!
        let text = try await ResumeInputReader.read(from: url)
        #expect(text.contains("Jane Doe"))
    }

    @Test func readsDOCXFile() async throws {
        let url = try makeDOCX(content: richContent)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ResumeInputReader.read(from: url)
        #expect(text.contains("Jane Doe"))
        #expect(text.contains("Software Engineer"))
        #expect(text.contains("Swift and Go"))
    }

    // MARK: - Text-layer PDF (PDFKit text extraction, no OCR)

    @Test func readsTextLayerPDF() async throws {
        // richContent is >100 chars so PDFKit text extraction is used directly.
        let url = try makeTextLayerPDF(content: richContent)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try await ResumeInputReader.read(from: url)
        #expect(text.contains("Jane Doe"))
        #expect(text.contains("Software Engineer"))
        #expect(text.contains("Swift and Go"))
    }

    @Test func sparseTextLayerFallsBackToOCR() async throws {
        // A text-layer PDF below the 100-char threshold triggers Vision OCR fallback.
        let url = try makeTextLayerPDF(content: shortContent)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try await ResumeInputReader.read(from: url)
        #expect(text.lowercased().contains("jane") || text.lowercased().contains("engineer"))
    }

    // MARK: - Image-only PDF (Vision OCR)

    @Test func readsImageOnlyPDF() async throws {
        // makeImagePDF strips the text layer — PDFKit returns empty, Vision OCR is required.
        let url = try makeImagePDF(content: richContent)
        defer { try? FileManager.default.removeItem(at: url) }
        let text = try await ResumeInputReader.read(from: url)
        #expect(text.count > 20)
        #expect(text.lowercased().contains("jane") || text.lowercased().contains("engineer"))
    }

    // MARK: - Error cases

    @Test func throwsForMissingPDF() async {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pdf")
        await #expect(throws: (any Error).self) {
            _ = try await ResumeInputReader.read(from: url)
        }
    }

    @Test func parsesTextLayerResumePDFIntoStructuredResume() async throws {
        let url = try makeTextLayerPDF(content: parsedResumeContent)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ResumeInputReader.read(from: url)
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: .pdf)
        let resume = Stages.parse(text: preprocessed.cleanedText, sourceKind: .pdf)

        #expect(resume.name == "JORDAN EXAMPLE")
        #expect(resume.experience.count == 3)
        #expect(resume.experience[0].company == "Northstar / Atlas")
        #expect(resume.experience[0].location == "Tokyo, Japan")
        #expect(resume.experience[0].bullets.count == 1)
        #expect(resume.education.count == 1)
        #expect(resume.education[0].degree == "Bachelor of Science, Computer Science | Minor: Mathematics")
        #expect(resume.skills.contains("Swift"))
        #expect(resume.skills.contains("LLM integration (Anthropic, OpenAI, OpenRouter, Ollama)"))
        #expect(resume.rawSections["Projects"]?.contains("provider-agnostic LLM orchestration layer") == true)
    }

    @Test func parsesImageOnlyResumePDFIntoStructuredResume() async throws {
        let url = try makeImagePDF(content: parsedResumeContent)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ResumeInputReader.read(from: url)
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: .pdf)
        let resume = Stages.parse(text: preprocessed.cleanedText, sourceKind: .pdf)

        #expect(resume.name == "JORDAN EXAMPLE")
        #expect(resume.experience.count == 3)
        #expect(resume.experience.contains { $0.company == "Beacon News" })
        #expect(resume.education.count == 1)
        #expect(resume.skills.contains("SwiftUI"))
        #expect(resume.rawSections["Projects"]?.contains("AI Mock Interview Coach") == true)
        #expect(resume.rawSections["Projects"]?.contains("Building a native macOS application for AI-driven mock interviews.") == true)
    }

    @Test func parsesResumeDOCXIntoStructuredResume() async throws {
        let url = try makeDOCX(content: parsedResumeContent)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ResumeInputReader.read(from: url)
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: .docx)
        let resume = Stages.parse(text: preprocessed.cleanedText, sourceKind: .docx)

        #expect(resume.name == "JORDAN EXAMPLE")
        #expect(resume.experience.count == 3)
        #expect(resume.experience[0].company == "Northstar / Atlas")
        #expect(resume.education.count == 1)
        #expect(resume.skills.contains("Swift"))
        #expect(resume.rawSections["Projects"]?.contains("AI Mock Interview Coach") == true)
        #expect(resume.rawSections["Projects"]?.contains("Building a native macOS application for AI-driven mock interviews.") == true)
    }

    @Test func readsDOCXPreservingSoftBreaksAndListParagraphs() async throws {
        let degreeRunXML =
            #"<w:r><w:t xml:space="preserve">Bachelor of Science, Computer Science  |  Minor: Mathematics</w:t>"#
            + #"<w:br w:type="textWrapping"/>"#
            + #"<w:t xml:space="preserve">Summa Cum Laude</w:t></w:r>"#
        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            <w:p>
              <w:r><w:t xml:space="preserve">Senior Software Engineer</w:t><w:br w:type="textWrapping"/></w:r>
              <w:r><w:t xml:space="preserve">Product-focused engineer</w:t></w:r>
            </w:p>
            <w:p>
              <w:pPr><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr></w:pPr>
              <w:r><w:t xml:space="preserve">Built provider-agnostic orchestration</w:t></w:r>
            </w:p>
            <w:p>
              <w:r><w:t xml:space="preserve">Wolt / DoorDash</w:t></w:r>
              <w:r><w:t xml:space="preserve">  </w:t></w:r>
              <w:r><w:t xml:space="preserve">|</w:t></w:r>
              <w:r><w:t xml:space="preserve">  Senior Software Engineer</w:t></w:r>
            </w:p>
            <w:p>
              \(degreeRunXML)
            </w:p>
            <w:sectPr/>
          </w:body>
        </w:document>
        """

        let url = try makeDOCX(documentXML: documentXML)
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try await ResumeInputReader.read(from: url)
        let preprocessed = ResumeTextPreprocessor.preprocess(text, sourceKind: .docx)

        #expect(text.contains("Senior Software Engineer\nProduct-focused engineer"))
        #expect(text.contains("• Built provider-agnostic orchestration"))
        #expect(text.contains("Wolt / DoorDash|  Senior Software Engineer"))
        #expect(text.contains("Minor: Mathematics\nSumma Cum Laude"))
        #expect(preprocessed.cleanedText.contains("Wolt / DoorDash | Senior Software Engineer"))
    }
}

// MARK: - PDF fixture helpers

extension ResumeInputReaderTests {
    private struct SetupError: Error { let message: String }

    private func makeDOCX(content: String) throws -> URL {
        let paragraphs = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                let escaped = xmlEscaped(String(line))
                if escaped.isEmpty {
                    return "<w:p/>"
                }
                return """
                <w:p>
                  <w:r><w:t xml:space="preserve">\(escaped)</w:t></w:r>
                </w:p>
                """
            }
            .joined(separator: "\n")

        let documentXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
          <w:body>
            \(paragraphs)
            <w:sectPr/>
          </w:body>
        </w:document>
        """

        return try makeDOCX(documentXML: documentXML)
    }

    private func makeDOCX(documentXML: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume_test_docx_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let relsDir = tempDir.appendingPathComponent("_rels", isDirectory: true)
        let wordDir = tempDir.appendingPathComponent("word", isDirectory: true)
        let wordRelsDir = wordDir.appendingPathComponent("_rels", isDirectory: true)
        try FileManager.default.createDirectory(at: relsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: wordRelsDir, withIntermediateDirectories: true)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
          <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
          <Default Extension="xml" ContentType="application/xml"/>
          <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        </Types>
        """.write(to: tempDir.appendingPathComponent("[Content_Types].xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
          <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
        </Relationships>
        """.write(to: relsDir.appendingPathComponent(".rels"), atomically: true, encoding: .utf8)

        try documentXML.write(to: wordDir.appendingPathComponent("document.xml"), atomically: true, encoding: .utf8)

        try """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
        """.write(to: wordRelsDir.appendingPathComponent("document.xml.rels"), atomically: true, encoding: .utf8)

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume_test_docx_\(UUID().uuidString).docx")
        try zipDirectory(source: tempDir, destination: outputURL)
        try FileManager.default.removeItem(at: tempDir)
        return outputURL
    }

    /// Creates a searchable (text-layer) PDF and returns a temp URL.
    private func makeTextLayerPDF(content: String) throws -> URL {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw SetupError(message: "Cannot create CGDataConsumer")
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SetupError(message: "Cannot create PDF CGContext")
        }

        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        let attrStr = NSAttributedString(string: content, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGPath(rect: CGRect(x: 50, y: 50, width: 512, height: 692), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
        ctx.beginPage(mediaBox: &mediaBox)
        CTFrameDraw(frame, ctx)
        ctx.endPage()
        ctx.closePDF()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume_test_text_\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return url
    }

    /// Creates an image-only PDF (no text layer) by rendering a text-layer PDF to a bitmap,
    /// then embedding that bitmap. PDFKit returns empty string for such pages; Vision OCR is required.
    private func makeImagePDF(content: String) throws -> URL {
        let textURL = try makeTextLayerPDF(content: content)
        defer { try? FileManager.default.removeItem(at: textURL) }

        guard let srcDoc = PDFDocument(url: textURL),
              let srcPage = srcDoc.page(at: 0) else {
            throw SetupError(message: "Cannot open intermediate text PDF")
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw SetupError(message: "Cannot create CGDataConsumer")
        }
        let bounds = srcPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let thumbSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let nsImage = srcPage.thumbnail(of: thumbSize, for: .mediaBox)

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SetupError(message: "Cannot extract CGImage from thumbnail")
        }

        var mediaBox = bounds
        guard let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw SetupError(message: "Cannot create image PDF CGContext")
        }
        ctx.beginPage(mediaBox: &mediaBox)
        ctx.draw(cgImage, in: mediaBox)   // image only — no text operators
        ctx.endPage()
        ctx.closePDF()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume_test_image_\(UUID().uuidString).pdf")
        try (data as Data).write(to: url)
        return url
    }

    private func zipDirectory(source: URL, destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-qr", destination.path, "."]
        process.currentDirectoryURL = source
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SetupError(message: "zip failed with status \(process.terminationStatus)")
        }
    }

    private func xmlEscaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
