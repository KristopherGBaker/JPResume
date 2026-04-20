import AppKit
import Foundation
import PDFKit
import SwiftDocX
import Vision
import ZIPFoundation

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
        if let extracted = try extractStructuredTextFromDOCX(url), !extracted.isEmpty {
            return extracted
        }

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

    private static func extractStructuredTextFromDOCX(_ url: URL) throws -> String? {
        guard let archive = Archive(url: url, accessMode: .read),
              let entry = archive["word/document.xml"] else {
            return nil
        }

        var data = Data()
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
        }

        let xml = try XMLDocument(data: data)
        let paragraphNodes = try xml.nodes(forXPath: "//*[local-name()='body']/*[local-name()='p']")
        guard !paragraphNodes.isEmpty else { return nil }

        let paragraphs = paragraphNodes.compactMap { node -> String? in
            guard let element = node as? XMLElement else { return nil }
            return textFromDOCXParagraph(element)
        }

        let text = paragraphs.joined(separator: "\n")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func textFromDOCXParagraph(_ paragraph: XMLElement) -> String {
        let isListItem = containsElement(named: "numPr", in: paragraph)
        var fragments: [String] = []
        collectDOCXText(from: paragraph, into: &fragments)

        let joined = fragments.joined()
        if joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ""
        }

        let normalizedLines = joined
            .components(separatedBy: "\n")
            .map { $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression) }

        if isListItem {
            var prefixed: [String] = []
            for line in normalizedLines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }
                prefixed.append("• " + trimmed)
            }
            return prefixed.joined(separator: "\n")
        }

        return normalizedLines.joined(separator: "\n")
    }

    private static func collectDOCXText(from node: XMLNode, into fragments: inout [String]) {
        if let element = node as? XMLElement {
            switch element.localName {
            case "t":
                fragments.append(element.stringValue ?? "")
                return
            case "br":
                fragments.append("\n")
                return
            default:
                break
            }
        }

        for child in node.children ?? [] {
            collectDOCXText(from: child, into: &fragments)
        }
    }

    private static func containsElement(named localName: String, in node: XMLNode) -> Bool {
        if let element = node as? XMLElement, element.localName == localName {
            return true
        }
        for child in node.children ?? [] {
            if containsElement(named: localName, in: child) {
                return true
            }
        }
        return false
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
