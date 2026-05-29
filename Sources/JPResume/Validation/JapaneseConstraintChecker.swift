import DocPipeline
import Foundation

/// Deterministic post-generation checker for Japanese resume outputs. Mirrors the hard
/// constraints listed in `SystemPrompts.rirekisho` / `SystemPrompts.shokumukeirekisho`
/// so we can detect violations without re-asking the LLM.
///
/// Violations (`DocPipeline.ConstraintViolation`) are intentionally surfaced as a list
/// rather than auto-fixed: rewriting formal Japanese requires the LLM. The self-critique
/// loop feeds these back as the targeted instructions for the next pass.
enum JapaneseConstraintChecker {

    // MARK: - Rirekisho

    /// Phrases the rirekisho prompt explicitly forbids. Substring match — covers
    /// 「確信しています」/「確信しております」without duplicating both forms.
    static let forbiddenRirekishoPhrases = [
        "確信して",          // covers 確信しております / 確信しています
        "即戦力として貢献",
        "大いに貢献",
        "飛躍的な成長",
        "必ず",              // catches 必ず〜できる / 必ずお役に立てる
        "圧倒的",
        "卓越した",
        "業界トップ"
    ]

    static func check(_ data: RirekishoData) -> [ConstraintViolation] {
        var violations: [ConstraintViolation] = []

        // R1: 「現在」/「現在に至る」rows must have an empty date cell.
        for (i, row) in data.workHistory.enumerated() {
            let hasCurrentMarker = row.description.contains("現在に至る") || row.description.contains("現在")
            if hasCurrentMarker && !row.date.trimmingCharacters(in: .whitespaces).isEmpty {
                violations.append(ConstraintViolation(
                    rule: "rirekisho.current_row_has_date",
                    field: "work_history[\(i)]",
                    message: "Row \(i) contains 「現在」/「現在に至る」but its date column is not blank " +
                             "(date=\"\(row.date)\"). The date column must be empty for the continuation row."
                ))
            }
        }

        // R2: If any work entry's description mentions a company-name + 現在, we expect a final
        // 「現在に至る」row with blank date. Heuristic: if any row description starts with a company
        // and the very last row is not a continuation row, flag it.
        if !data.workHistory.isEmpty,
           let last = data.workHistory.last,
           workHistoryMentionsCurrent(data.workHistory),
           !last.description.contains("現在に至る") {
            violations.append(ConstraintViolation(
                rule: "rirekisho.missing_continuation_row",
                field: "work_history",
                message: "Work history references a current role but does not end with a 「現在に至る」 " +
                         "continuation row (blank date, description=「現在に至る」)."
            ))
        }

        // R3: Forbidden hype phrases in 志望動機.
        if let motivation = data.motivation, !motivation.isEmpty {
            for phrase in forbiddenRirekishoPhrases where motivation.contains(phrase) {
                violations.append(ConstraintViolation(
                    rule: "rirekisho.forbidden_phrase",
                    field: "motivation",
                    message: "志望動機 contains forbidden phrase 「\(phrase)」. Rewrite in a modest, " +
                             "factual register (e.g., 〜してまいりました, 〜の経験がございます)."
                ))
            }
        }

        return violations
    }

    /// Heuristic: any non-continuation row whose description doesn't itself say 「退職」/「離職」
    /// and where the resume normalization marked some role current. We don't have that flag
    /// here, so we approximate: if any row mentions 「入社」without a corresponding 「退職」 row
    /// later, treat as current. Conservative — flags when ambiguous so the LLM can confirm.
    private static func workHistoryMentionsCurrent(_ rows: [DateDescription]) -> Bool {
        var openCompanyCount = 0
        for row in rows {
            if row.description.contains("入社") { openCompanyCount += 1 }
            if row.description.contains("退職") || row.description.contains("離職") { openCompanyCount -= 1 }
        }
        return openCompanyCount > 0
    }

    // MARK: - Shokumukeirekisho

    /// Catches: same opening clause, both starting with 「これまで」or「〇年以上」, metrics duplicated.
    static func check(_ data: ShokumukeirekishoData) -> [ConstraintViolation] {
        var violations: [ConstraintViolation] = []
        guard let pr = data.selfPr, !pr.isEmpty else { return violations }
        let summary = data.careerSummary

        let summaryFirst = firstSentence(summary)
        let prFirst = firstSentence(pr)

        // S1: first sentences must be meaningfully different.
        if summaryFirst.count >= 10 && prFirst.count >= 10 {
            let prefixLen = min(15, min(summaryFirst.count, prFirst.count))
            if summaryFirst.prefix(prefixLen) == prFirst.prefix(prefixLen) {
                violations.append(ConstraintViolation(
                    rule: "shokumu.duplicate_opening",
                    field: "self_pr",
                    message: "First sentence of 自己PR starts the same as 職務要約. They must use " +
                             "different topics and framing (自己PR = soft strengths; 職務要約 = career arc)."
                ))
            }
        }

        // S2: both opening with 「これまで」.
        if summaryFirst.hasPrefix("これまで") && prFirst.hasPrefix("これまで") {
            violations.append(ConstraintViolation(
                rule: "shokumu.duplicate_kore_made_opening",
                field: "self_pr",
                message: "Both 職務要約 and 自己PR start with 「これまで」. Vary the openings."
            ))
        }

        // S3: both opening with a year count (e.g. 「10年以上」, 「13年にわたり」).
        if openingHasYearCount(summaryFirst) && openingHasYearCount(prFirst) {
            violations.append(ConstraintViolation(
                rule: "shokumu.duplicate_year_count_opening",
                field: "self_pr",
                message: "Both 職務要約 and 自己PR open with a year-count phrasing. Only one section " +
                         "should reference total years; the other should foreground different content."
            ))
        }

        // S4: any quantified metric appearing in both sections.
        let summaryMetrics = extractMetrics(summary)
        let prMetrics = extractMetrics(pr)
        let dupes = summaryMetrics.intersection(prMetrics)
        if !dupes.isEmpty {
            violations.append(ConstraintViolation(
                rule: "shokumu.metric_duplicated",
                field: "self_pr",
                message: "Metric(s) \(dupes.sorted().joined(separator: ", ")) appear in both " +
                         "職務要約 and 自己PR. Mention each quantified result in only one section."
            ))
        }

        return violations
    }

    // MARK: - Helpers

    private static func firstSentence(_ text: String) -> String {
        if let end = text.firstIndex(of: "。") {
            return String(text[..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func openingHasYearCount(_ sentence: String) -> Bool {
        // Match e.g. 「10年以上」、「13年にわたり」、「20年以上にわたり」in the opening clause.
        let opening = String(sentence.prefix(20))
        return opening.range(of: #"^[0-9０-９]+年(以上|にわたり|間)"#,
                              options: .regularExpression) != nil
    }

    /// Returns the set of numeric+unit tokens (e.g. "29.8%", "10年", "27000件") that look like
    /// quantified outcomes. ASCII + full-width digits, common JP business units.
    private static func extractMetrics(_ text: String) -> Set<String> {
        let pattern = #"[0-9０-９][0-9０-９,，.]*\s*(%|％|年|件|名|人|円|時間|分|倍|万|億|社)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        var out: Set<String> = []
        regex.enumerateMatches(in: text, range: nsrange) { match, _, _ in
            guard let match, let range = Range(match.range, in: text) else { return }
            out.insert(text[range].trimmingCharacters(in: .whitespaces))
        }
        return out
    }
}
