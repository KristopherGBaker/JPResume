import AppKit
import CoreText
import Foundation

enum PDFFont {
    /// Find a suitable Japanese font, preferring Hiragino Sans.
    static func japanese(size: CGFloat) -> NSFont {
        let candidates = [
            "HiraginoSans-W3",
            "HiraKakuProN-W3",
            "HiraKakuPro-W3",
            "STHeitiSC-Light",
            "AppleSDGothicNeo-Regular",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.systemFont(ofSize: size)
    }

    static func japaneseBold(size: CGFloat) -> NSFont {
        let candidates = [
            "HiraginoSans-W6",
            "HiraKakuProN-W6",
            "HiraKakuPro-W6",
            "STHeitiSC-Medium",
            "AppleSDGothicNeo-Bold",
        ]
        for name in candidates {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.boldSystemFont(ofSize: size)
    }
}
