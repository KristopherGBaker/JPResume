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

    // MARK: - Markdown

    @Test func readsMarkdownFile() async throws {
        let url = Bundle.module.url(forResource: "sample_resume", withExtension: "md", subdirectory: "Fixtures")!
        let text = try await ResumeInputReader.read(from: url)
        #expect(text.contains("Jane Doe"))
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
}

// MARK: - PDF fixture helpers

extension ResumeInputReaderTests {
    private struct SetupError: Error { let message: String }

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
        ctx.beginPage(mediaBox: &mediaBox)

        let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        let attrStr = NSAttributedString(string: content, attributes: [.font: font])
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let path = CGPath(rect: CGRect(x: 50, y: 50, width: 512, height: 692), transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: 0), path, nil)
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

        let bounds = srcPage.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let thumbSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let nsImage = srcPage.thumbnail(of: thumbSize, for: .mediaBox)

        guard let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw SetupError(message: "Cannot extract CGImage from thumbnail")
        }

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw SetupError(message: "Cannot create CGDataConsumer")
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
}
