import Foundation

/// Deterministic post-generation text polish for Japanese resume output.
/// Applies normalization rules to fix awkward translations, inconsistent phrasing,
/// and computed-value mismatches without requiring another LLM call.
enum JapanesePolishRules {

    // MARK: - Top-level entry points

    /// Polish a ShokumukeirekishoData using derived experience data.
    static func polish(
        _ data: ShokumukeirekishoData,
        derived: DerivedExperience?
    ) -> ShokumukeirekishoData {
        var result = data

        // 1. Replace experience year counts with computed values
        if let derived = derived {
            result.careerSummary = replaceExperienceYears(result.careerSummary, derived: derived)
            result.selfPr = result.selfPr.map { replaceExperienceYears($0, derived: derived) }
        }

        // 2. Normalize Japanese phrases
        result.careerSummary = normalizeJapanesePhrases(result.careerSummary)
        result.selfPr = result.selfPr.map { normalizeJapanesePhrases($0) }

        for i in result.workDetails.indices {
            result.workDetails[i].responsibilities = result.workDetails[i].responsibilities.map {
                normalizeJapanesePhrases($0)
            }
            result.workDetails[i].achievements = result.workDetails[i].achievements.map {
                normalizeJapanesePhrases($0)
            }
        }

        // 3. Normalize certification wording in technical skills
        for (key, skills) in result.technicalSkills {
            result.technicalSkills[key] = skills.map { normalizeCertification($0) }
        }

        // 4. Deduplicate claims between career summary and self-PR
        result = deduplicateSections(result)

        // 5. Normalize company names in work details
        for i in result.workDetails.indices {
            result.workDetails[i].companyName = normalizeCompanyName(result.workDetails[i].companyName)
        }

        return result
    }

    /// Polish a RirekishoData using derived experience data.
    static func polish(
        _ data: RirekishoData,
        derived: DerivedExperience?
    ) -> RirekishoData {
        var result = data

        // Normalize motivation text
        if let derived = derived {
            result.motivation = result.motivation.map { replaceExperienceYears($0, derived: derived) }
        }
        result.motivation = result.motivation.map { normalizeJapanesePhrases($0) }

        // Normalize license/certification descriptions
        result.licenses = result.licenses.map { entry in
            DateDescription(entry.date, normalizeCertification(entry.description))
        }

        // Normalize work history company names
        result.workHistory = result.workHistory.map { entry in
            DateDescription(entry.date, normalizeCompanyName(entry.description))
        }

        return result
    }

    // MARK: - Experience year replacement

    /// Pattern: "X年以上" or "X年間" or "約X年"
    /// Replace with computed values from DerivedExperience.
    static func replaceExperienceYears(_ text: String, derived: DerivedExperience) -> String {
        var result = text
        let total = derived.totalSoftwareYears

        // Replace generic "X年以上のソフトウェア/開発/エンジニアリング経験" patterns
        let softwarePatterns = [
            "ソフトウェア開発経験", "開発経験", "エンジニアリング経験",
            "ソフトウェアエンジニアリング経験", "開発実績", "実務経験",
            "ソフトウェア開発の経験", "ソフトウェア開発の実務経験"
        ]
        for suffix in softwarePatterns {
            // Match "X年以上の<suffix>" or "約X年の<suffix>" or "X年間の<suffix>"
            let patterns = [
                "\\d+年以上の\(NSRegularExpression.escapedPattern(for: suffix))",
                "約\\d+年の\(NSRegularExpression.escapedPattern(for: suffix))",
                "\\d+年間の\(NSRegularExpression.escapedPattern(for: suffix))",
                "\\d+年以上にわたる\(NSRegularExpression.escapedPattern(for: suffix))"
            ]
            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern) {
                    let range = NSRange(result.startIndex..., in: result)
                    result = regex.stringByReplacingMatches(
                        in: result, range: range,
                        withTemplate: "\(total)年以上の\(suffix)"
                    )
                }
            }
        }

        // Replace iOS-specific experience counts if available
        if let iosYears = derived.iosYears {
            let iosPatterns = [
                "iOS開発経験", "iOS開発の経験", "iOSアプリ開発経験",
                "モバイル開発経験", "モバイルアプリ開発経験"
            ]
            for suffix in iosPatterns {
                let patterns = [
                    "\\d+年以上の\(NSRegularExpression.escapedPattern(for: suffix))",
                    "約\\d+年の\(NSRegularExpression.escapedPattern(for: suffix))",
                    "\\d+年間の\(NSRegularExpression.escapedPattern(for: suffix))"
                ]
                for pattern in patterns {
                    if let regex = try? NSRegularExpression(pattern: pattern) {
                        let range = NSRange(result.startIndex..., in: result)
                        result = regex.stringByReplacingMatches(
                            in: result, range: range,
                            withTemplate: "\(iosYears)年以上の\(suffix)"
                        )
                    }
                }
            }
        }

        return result
    }

    // MARK: - Japanese phrase normalization

    /// Phrase replacement table: awkward/literal translations → natural Japanese.
    static let phraseReplacements: [(pattern: String, replacement: String)] = [
        // Certification wording
        ("日本語能力試験 N(\\d) 取得", "日本語能力試験N$1合格"),
        ("日本語能力試験N(\\d) 取得", "日本語能力試験N$1合格"),
        ("日本語能力試験 N(\\d)取得", "日本語能力試験N$1合格"),

        // Jargon normalization
        ("フロントエンドDRI（直接責任者）", "iOS開発の主担当"),
        ("フロントエンドDRI", "iOS開発の主担当"),
        ("DRI（直接責任者）", "主担当"),

        ("クロスチーム", "複数チーム横断"),
        ("クロスファンクショナル", "職種横断"),
        ("クロスファンクショナルチーム", "職種横断チーム"),

        ("バックエンド駆動型UI", "サーバー駆動型UI"),
        ("バックエンドドリブンUI", "サーバー駆動型UI"),

        ("追加購読者", "増分会員登録"),
        ("追加サブスクライバー", "新規会員獲得"),

        // Style normalization
        ("スクラムマスター", "スクラムマスター"),  // keep as-is (already correct)
        ("アジャイルスクラム", "アジャイル・スクラム"),
        ("CI/CD", "CI/CD"),  // keep English acronyms

        // Common awkward translations
        ("ゼロから構築", "新規構築"),
        ("ゼロからの構築", "新規構築"),
        ("スケーラビリティ", "拡張性"),
        ("リファクタリング", "リファクタリング"),  // keep as-is, widely used
        ("オンボーディング", "新人教育・導入支援"),
        ("メンタリング", "メンタリング"),  // keep as-is
        ("コードレビュー", "コードレビュー"),  // keep as-is
    ]

    static func normalizeJapanesePhrases(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in phraseReplacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    // MARK: - Certification normalization

    static let certificationReplacements: [(pattern: String, replacement: String)] = [
        ("日本語能力試験 N(\\d) 取得", "日本語能力試験N$1合格"),
        ("日本語能力試験N(\\d) 取得", "日本語能力試験N$1合格"),
        ("日本語能力試験N(\\d)取得", "日本語能力試験N$1合格"),
        ("JLPT N(\\d) 取得", "日本語能力試験N$1合格"),
        ("JLPT N(\\d)取得", "日本語能力試験N$1合格"),
        ("JLPT N(\\d)", "日本語能力試験N$1合格"),
    ]

    static func normalizeCertification(_ text: String) -> String {
        var result = text
        for (pattern, replacement) in certificationReplacements {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: replacement)
        }
        return result
    }

    // MARK: - Company name normalization

    /// Ensure Japanese company names use consistent formatting.
    static func normalizeCompanyName(_ text: String) -> String {
        var result = text

        // "Inc." / "Inc" / ", Inc." → remove from Japanese context (株式会社 is used instead)
        // But only if 株式会社 is already present
        if result.contains("株式会社") {
            result = result.replacingOccurrences(of: ", Inc.", with: "")
            result = result.replacingOccurrences(of: " Inc.", with: "")
            result = result.replacingOccurrences(of: " Inc", with: "")
            result = result.replacingOccurrences(of: ",Inc.", with: "")
        }

        // "LLC" / ", LLC" → remove if 合同会社 present
        if result.contains("合同会社") {
            result = result.replacingOccurrences(of: ", LLC", with: "")
            result = result.replacingOccurrences(of: " LLC", with: "")
        }

        return result
    }

    // MARK: - Section deduplication

    /// Remove sentences from selfPr that appear verbatim (or near-verbatim) in careerSummary.
    static func deduplicateSections(_ data: ShokumukeirekishoData) -> ShokumukeirekishoData {
        var result = data
        guard let selfPr = result.selfPr, !selfPr.isEmpty else { return result }

        let summarySentences = extractSentences(result.careerSummary)
        let prSentences = extractSentences(selfPr)

        guard !summarySentences.isEmpty && !prSentences.isEmpty else { return result }

        // Find the first sentence of selfPr — if it's too similar to the first sentence
        // of careerSummary, remove it from selfPr
        if let firstPr = prSentences.first,
           let firstSummary = summarySentences.first,
           sentenceSimilarity(firstPr, firstSummary) > 0.6 {
            // Remove the duplicate lead sentence from selfPr
            let remaining = prSentences.dropFirst()
            if remaining.isEmpty {
                // Don't empty the whole section — leave as-is
                return result
            }
            result.selfPr = remaining.joined(separator: "")
        }

        return result
    }

    /// Split Japanese text into sentences by common delimiters.
    static func extractSentences(_ text: String) -> [String] {
        // Split on 。 but keep the delimiter with the preceding sentence
        var sentences: [String] = []
        var current = ""
        for char in text {
            current.append(char)
            if char == "。" || char == "\n" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }
        return sentences
    }

    /// Simple character-overlap similarity between two Japanese sentences.
    /// Returns 0.0–1.0 where 1.0 is identical.
    static func sentenceSimilarity(_ a: String, _ b: String) -> Double {
        guard !a.isEmpty && !b.isEmpty else { return 0.0 }
        let setA = Set(a)
        let setB = Set(b)
        let intersection = setA.intersection(setB).count
        let union = setA.union(setB).count
        return union > 0 ? Double(intersection) / Double(union) : 0.0
    }
}
