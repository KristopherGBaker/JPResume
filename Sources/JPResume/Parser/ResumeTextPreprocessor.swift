import Foundation

struct PreprocessedResumeText: Sendable {
    let originalText: String
    let cleanedText: String
    let notes: [String]
}

enum ResumeTextPreprocessor {
    static func preprocess(_ text: String, sourceKind: ResumeSourceKind) -> PreprocessedResumeText {
        let normalized = normalizeLineEndings(in: text)
        guard sourceKind != .markdown else {
            return PreprocessedResumeText(originalText: normalized, cleanedText: normalized, notes: [])
        }

        var notes: [String] = []
        var lines = normalized.components(separatedBy: "\n").map {
            $0.replacingOccurrences(of: #"\s+$"#, with: "", options: .regularExpression)
        }

        let bulletFixed = mergeStandaloneBulletLines(lines)
        lines = bulletFixed.lines
        if bulletFixed.changed {
            notes.append("Merged standalone bullet markers with following text lines")
        }

        let normalizedPipes = normalizePipeDelimiters(lines)
        lines = normalizedPipes.lines
        if normalizedPipes.changed {
            notes.append("Normalized standalone pipe delimiters between text segments")
        }

        let wrappedBullets = joinWrappedBulletLines(lines)
        lines = wrappedBullets.lines
        if wrappedBullets.changed {
            notes.append("Joined wrapped bullet text lines")
        }

        let correctedOCR = applyOCRCorrections(lines)
        lines = correctedOCR.lines
        if correctedOCR.changed {
            notes.append("Applied conservative OCR corrections for common tech terms")
        }

        let collapsed = collapseRepeatedBlankLines(lines)
        if collapsed != lines {
            notes.append("Collapsed repeated blank lines")
        }

        return PreprocessedResumeText(
            originalText: normalized,
            cleanedText: collapsed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes
        )
    }

    private static func normalizeLineEndings(in text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    private static func mergeStandaloneBulletLines(_ lines: [String]) -> (lines: [String], changed: Bool) {
        var result: [String] = []
        var index = 0
        var changed = false

        while index < lines.count {
            let current = lines[index].trimmingCharacters(in: .whitespaces)
            if isStandaloneBullet(current) {
                var nextIndex = index + 1
                while nextIndex < lines.count,
                      lines[nextIndex].trimmingCharacters(in: .whitespaces).isEmpty {
                    nextIndex += 1
                }
                if nextIndex < lines.count {
                    result.append("• " + lines[nextIndex].trimmingCharacters(in: .whitespaces))
                    changed = true
                    index = nextIndex + 1
                    continue
                }
            }
            result.append(lines[index])
            index += 1
        }

        return (result, changed)
    }

    private static func joinWrappedBulletLines(_ lines: [String]) -> (lines: [String], changed: Bool) {
        var result: [String] = []
        var changed = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let last = result.last else {
                result.append(line)
                continue
            }

            if isBulletLine(last.trimmingCharacters(in: .whitespaces)),
               isBulletContinuation(trimmed) {
                result[result.count - 1] = last + " " + trimmed
                changed = true
            } else {
                result.append(line)
            }
        }

        return (result, changed)
    }

    private static func normalizePipeDelimiters(_ lines: [String]) -> (lines: [String], changed: Bool) {
        var changed = false
        let normalized = lines.map { line in
            let updated = line.replacingOccurrences(
                of: #"\s*\|\s*"#,
                with: " | ",
                options: .regularExpression
            )
            if updated != line {
                changed = true
            }
            return updated
        }
        return (normalized, changed)
    }

    private static func collapseRepeatedBlankLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        var previousBlank = false

        for line in lines {
            let blank = line.trimmingCharacters(in: .whitespaces).isEmpty
            if blank && previousBlank { continue }
            result.append(line)
            previousBlank = blank
        }
        return result
    }

    private static func applyOCRCorrections(_ lines: [String]) -> (lines: [String], changed: Bool) {
        let replacements: [(pattern: String, replacement: String)] = [
            (#"\bAl\b"#, "AI"),
            (#"\bUl\b"#, "UI"),
            (#"\bOpenAl\b"#, "OpenAI"),
            (#"\bSwiftUl\b"#, "SwiftUI"),
            (#"\bSQlite\b"#, "SQLite"),
            (#"\b5Qlite\b"#, "SQLite"),
            (#"\bRFs\b"#, "RFCs"),
        ]

        var changed = false
        let corrected = lines.map { line in
            var updated = line
            for replacement in replacements {
                let next = updated.replacingOccurrences(
                    of: replacement.pattern,
                    with: replacement.replacement,
                    options: .regularExpression
                )
                if next != updated {
                    changed = true
                    updated = next
                }
            }
            return updated
        }
        return (corrected, changed)
    }

    private static func isStandaloneBullet(_ line: String) -> Bool {
        ["•", "●", "-", "*"].contains(line)
    }

    private static func isBulletLine(_ line: String) -> Bool {
        line.range(of: #"^(?:[-*•●])\s+"#, options: .regularExpression) != nil
    }

    private static func isBulletContinuation(_ line: String) -> Bool {
        guard !line.isEmpty else { return false }
        if isStandaloneBullet(line) || isBulletLine(line) || isLikelySectionHeading(line) || looksLikeEntryHeading(line) {
            return false
        }
        return true
    }

    private static func isLikelySectionHeading(_ line: String) -> Bool {
        guard !line.contains("|") else { return false }
        return SectionClassifier.classify(line) != nil
    }

    private static func looksLikeEntryHeading(_ line: String) -> Bool {
        line.contains(" | ")
    }
}
