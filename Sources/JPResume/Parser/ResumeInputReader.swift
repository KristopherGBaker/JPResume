import AppKit
import Foundation
import PDFKit
import SwiftDocX
import Vision

enum ResumeInputReader {
    enum Error: Swift.Error, LocalizedError {
        case cannotOpenDOCX(URL)
        case cannotOpenPDF(URL)
        case noExtractableText(URL)

        var errorDescription: String? {
            switch self {
            case .cannotOpenDOCX(let url): return "Cannot open DOCX: \(url.lastPathComponent)"
            case .cannotOpenPDF(let url): return "Cannot open PDF: \(url.lastPathComponent)"
            case .noExtractableText(let url): return "No extractable text found in: \(url.lastPathComponent)"
            }
        }
    }

    // Minimum character count to consider text-layer extraction successful.
    private static let textLayerThreshold = 100

    static func read(from url: URL) async throws -> String {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return try await extractFromPDF(url)
        case "docx":
            return try extractFromDOCX(url)
        default:
            return try String(contentsOf: url, encoding: .utf8)
        }
    }

    // MARK: - DOCX extraction

    private static func extractFromDOCX(_ url: URL) throws -> String {
        guard let document = try? Document(contentsOf: url) else {
            throw Error.cannotOpenDOCX(url)
        }

        let text = document.text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: CharacterSet.whitespacesAndNewlines) }
            .joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        guard !text.isEmpty else {
            throw Error.noExtractableText(url)
        }
        return text
    }

    // MARK: - PDF extraction

    private static func extractFromPDF(_ url: URL) async throws -> String {
        guard let doc = PDFDocument(url: url) else {
            throw Error.cannotOpenPDF(url)
        }
        let text = (0..<doc.pageCount)
            .compactMap { doc.page(at: $0)?.string }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.count >= textLayerThreshold {
            return text
        }

        print("  PDF has no text layer — falling back to Vision OCR...")
        return try await ocrPDF(doc)
    }

    // MARK: - Vision OCR

    private static func ocrPDF(_ doc: PDFDocument) async throws -> String {
        var pages: [String] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i),
                  let image = renderPage(page) else { continue }
            let pageText = try await recognizeText(in: image)
            if !pageText.isEmpty { pages.append(pageText) }
        }
        let result = pages.joined(separator: "\n")
        guard !result.isEmpty else { throw Error.noExtractableText(doc.documentURL ?? URL(fileURLWithPath: "")) }
        return result
    }

    private static func renderPage(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    private static func recognizeText(in image: CGImage) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { req, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let lines = (req.results as? [VNRecognizedTextObservation])?
                    .compactMap { $0.topCandidates(1).first?.string } ?? []
                continuation.resume(returning: lines.joined(separator: "\n"))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
