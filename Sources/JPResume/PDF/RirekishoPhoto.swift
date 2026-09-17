import CoreGraphics
import Foundation
import ImageIO

/// The 3×4cm 写真 on a 履歴書: locating the file named by `photo_path` and
/// fitting it to the box without distorting the candidate's face.
enum RirekishoPhoto {
    /// Extensions ImageIO can decode and a printer will accept.
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tiff", "tif"]

    /// 4096px across is well past what a 30×40mm box can print; anything larger only
    /// bloats the PDF.
    private static let maxPixelSize = 4096

    /// Resolve `path` to a readable file. Absolute and `~`-prefixed paths are used as
    /// written; a relative path is tried against each base in order (the directory that
    /// holds the config first, then the workspace, then the current directory).
    static func resolve(_ path: String?, relativeTo bases: [URL]) -> URL? {
        guard let path, !path.isEmpty else { return nil }
        let expanded = (path as NSString).expandingTildeInPath
        let candidates: [URL]
        if expanded.hasPrefix("/") {
            candidates = [URL(fileURLWithPath: expanded)]
        } else {
            candidates = bases.map { $0.appendingPathComponent(expanded).standardizedFileURL }
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Decode the image. Uses ImageIO's transforming thumbnail path so that EXIF-rotated
    /// camera photos come back upright, and so an oversized original is downsampled
    /// before it lands in the PDF.
    static func load(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Draw `image` filling `rect` entirely, preserving its aspect ratio and cropping
    /// the overflowing axis evenly from both sides.
    static func draw(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        let imageW = CGFloat(image.width)
        let imageH = CGFloat(image.height)
        guard imageW > 0, imageH > 0, rect.width > 0, rect.height > 0 else { return }

        let scale = max(rect.width / imageW, rect.height / imageH)
        let drawn = CGSize(width: imageW * scale, height: imageH * scale)
        let drawRect = CGRect(x: rect.midX - drawn.width / 2,
                              y: rect.midY - drawn.height / 2,
                              width: drawn.width, height: drawn.height)

        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.interpolationQuality = .high
        ctx.draw(image, in: drawRect)
        ctx.restoreGState()
    }
}
