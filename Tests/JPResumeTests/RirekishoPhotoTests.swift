import CoreGraphics
import ImageIO
import Testing
@testable import jpresume
import Foundation
import UniformTypeIdentifiers

@Suite("履歴書 photo")
struct RirekishoPhotoTests {

    // MARK: Helpers

    /// A solid-colour PNG on disk, so the tests exercise the real decode path.
    /// Written through ImageIO rather than AppKit: Swift Testing runs these off the
    /// main thread, where NSGraphicsContext is not safe.
    private func writePNG(width: Int, height: Int, to url: URL) throws {
        let image = makeImage(width: width, height: height)
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
    }

    private func tempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("jpresume-photo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func sampleData(photoPath: String?) -> RirekishoData {
        RirekishoData(
            creationDate: "2026年9月17日",
            nameKanji: "田中太郎",
            nameFurigana: "タナカタロウ",
            dateOfBirth: "1990年1月1日",
            photoPath: photoPath,
            educationHistory: [DateDescription("2010年4月", "東京大学 工学部 入学")],
            workHistory: [DateDescription("2014年4月", "株式会社ABC 入社")],
            licenses: []
        )
    }

    // MARK: Resolution

    @Test func resolvesRelativePathAgainstBases() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("photo.png")
        try writePNG(width: 30, height: 40, to: photo)

        let resolved = RirekishoPhoto.resolve("photo.png", relativeTo: [dir])
        #expect(resolved?.standardizedFileURL == photo.standardizedFileURL)
    }

    @Test func prefersTheFirstBaseThatHasTheFile() throws {
        let first = try tempDir()
        let second = try tempDir()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try writePNG(width: 30, height: 40, to: first.appendingPathComponent("photo.png"))
        try writePNG(width: 30, height: 40, to: second.appendingPathComponent("photo.png"))

        let resolved = RirekishoPhoto.resolve("photo.png", relativeTo: [second, first])
        #expect(resolved?.standardizedFileURL == second.appendingPathComponent("photo.png").standardizedFileURL)
    }

    @Test func resolvesAbsolutePathIgnoringBases() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("headshot.png")
        try writePNG(width: 30, height: 40, to: photo)

        let resolved = RirekishoPhoto.resolve(photo.path, relativeTo: [])
        #expect(resolved?.standardizedFileURL == photo.standardizedFileURL)
    }

    @Test func returnsNilForMissingOrEmptyPaths() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        #expect(RirekishoPhoto.resolve(nil, relativeTo: [dir]) == nil)
        #expect(RirekishoPhoto.resolve("", relativeTo: [dir]) == nil)
        #expect(RirekishoPhoto.resolve("nope.png", relativeTo: [dir]) == nil)
    }

    // MARK: Rendering

    @Test func rendersThePhotoIntoThePDF() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = dir.appendingPathComponent("photo.png")
        try writePNG(width: 300, height: 400, to: photo)

        let withPhoto = dir.appendingPathComponent("with.pdf")
        let withoutPhoto = dir.appendingPathComponent("without.pdf")
        try RirekishoPDFRenderer.render(data: sampleData(photoPath: "photo.png"),
                                        to: withPhoto, photo: photo)
        try RirekishoPDFRenderer.render(data: sampleData(photoPath: nil), to: withoutPhoto)

        let withSize = try Data(contentsOf: withPhoto).count
        let withoutSize = try Data(contentsOf: withoutPhoto).count
        #expect(withSize > withoutSize)

        let doc = try #require(CGPDFDocument(withPhoto as CFURL))
        #expect(doc.numberOfPages >= 1)
    }

    @Test func rendersAnEmptyBoxWhenThePhotoIsUnreadable() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notAnImage = dir.appendingPathComponent("photo.png")
        try Data("this is not a PNG".utf8).write(to: notAnImage)

        let out = dir.appendingPathComponent("out.pdf")
        try RirekishoPDFRenderer.render(data: sampleData(photoPath: "photo.png"),
                                        to: out, photo: notAnImage)

        let doc = try #require(CGPDFDocument(out as CFURL))
        #expect(doc.numberOfPages >= 1)
        #expect(RirekishoPhoto.load(notAnImage) == nil)
    }

    // MARK: Aspect ratio

    @Test func aspectFillRestoresTheClipItUsed() throws {
        // A wide source drawn into the tall 3×4 box overflows horizontally; the clip
        // that hides the overflow must not leak into whatever is drawn next.
        let box = CGRect(x: 0, y: 10, width: 30, height: 40)
        let image = makeImage(width: 80, height: 40)
        let ctx = try #require(CGContext(data: nil, width: 60, height: 80, bitsPerComponent: 8,
                                         bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        let before = ctx.boundingBoxOfClipPath
        RirekishoPhoto.draw(image, in: box, ctx: ctx)
        #expect(ctx.boundingBoxOfClipPath == before)
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue)!
        ctx.setFillColor(gray: 0.5, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage()!
    }
}
