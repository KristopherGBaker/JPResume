import Foundation

/// Post-normalization consistency checker and repairer.
/// Computes derived experience fields, detects chronology problems,
/// and applies safe repairs before the data reaches JP generation.
enum ResumeConsistencyChecker {

    /// Run all checks and repairs on a normalized resume, returning the repaired copy.
    static func check(_ resume: NormalizedResume) -> NormalizedResume {
        var result = resume
        var repairs: [RepairNote] = []

        // 1. Sort experience chronologically
        result.experience = sortChronologically(result.experience)

        // 2. Repair overlapping dates
        result.experience = repairOverlaps(result.experience, repairs: &repairs)

        // 3. Fix isCurrent inconsistencies
        result.experience = repairIsCurrentFlags(result.experience, repairs: &repairs)

        // 4. Compute derived experience
        result.derivedExperience = computeDerivedExperience(result.experience)

        result.repairs = resume.repairs + repairs
        return result
    }

    // MARK: - Chronological sorting

    static func sortChronologically(_ entries: [NormalizedWorkEntry]) -> [NormalizedWorkEntry] {
        entries.sorted { a, b in
            guard let aStart = a.startDate else { return false }
            guard let bStart = b.startDate else { return true }
            return aStart < bStart
        }
    }

    // MARK: - Overlap repair

    /// Detect and repair overlapping roles where the overlap is likely unintentional.
    /// A freelance/contract role starting before the prior full-time role ends is repaired
    /// by pushing the later role's start to the prior role's end month.
    static func repairOverlaps(
        _ entries: [NormalizedWorkEntry],
        repairs: inout [RepairNote]
    ) -> [NormalizedWorkEntry] {
        var result = entries
        guard result.count > 1 else { return result }

        for i in 0..<(result.count - 1) {
            let current = result[i]
            let next = result[i + 1]

            guard !current.isCurrent else { continue }
            guard let currentEnd = current.endDate,
                  let nextStart = next.startDate else { continue }

            // Only repair if next starts strictly before current ends
            guard nextStart < currentEnd else { continue }

            // Repair: push next start to current end
            let oldStart = nextStart
            result[i + 1].startDate = currentEnd

            repairs.append(RepairNote(
                field: "experience[\(i + 1)].start_date",
                original: formatDate(oldStart),
                repaired: formatDate(currentEnd),
                reason: "Overlap with \(current.company): moved start date to end of prior role"
            ))
        }

        return result
    }

    // MARK: - isCurrent flag repair

    /// Ensure only the last role (by start date) has isCurrent=true,
    /// and roles with endDates are not marked current.
    static func repairIsCurrentFlags(
        _ entries: [NormalizedWorkEntry],
        repairs: inout [RepairNote]
    ) -> [NormalizedWorkEntry] {
        var result = entries
        guard !result.isEmpty else { return result }

        for i in 0..<result.count {
            let entry = result[i]

            // If marked current but has an end date, clear isCurrent
            if entry.isCurrent && entry.endDate != nil {
                result[i].isCurrent = false
                repairs.append(RepairNote(
                    field: "experience[\(i)].is_current",
                    original: "true",
                    repaired: "false",
                    reason: "\(entry.company): has end date but was marked current"
                ))
            }

            // If it's not the last entry and is current with no end date,
            // it's likely wrong unless it's genuinely concurrent
            if entry.isCurrent && entry.endDate == nil && i < result.count - 1 {
                // Only repair if a later role also exists with a start date after this one
                let laterRoles = result[(i + 1)...]
                let hasLaterRole = laterRoles.contains { later in
                    guard let laterStart = later.startDate,
                          let thisStart = entry.startDate else { return false }
                    return laterStart > thisStart
                }
                if hasLaterRole {
                    result[i].isCurrent = false
                    // Use the next role's start date as a reasonable end date
                    if let nextStart = result[i + 1].startDate {
                        result[i].endDate = nextStart
                        repairs.append(RepairNote(
                            field: "experience[\(i)].is_current",
                            original: "true (no end date)",
                            repaired: "false, end_date set to \(formatDate(nextStart))",
                            reason: "\(entry.company): marked current but later roles exist"
                        ))
                    }
                }
            }
        }

        return result
    }

    // MARK: - Derived experience computation

    static func computeDerivedExperience(_ entries: [NormalizedWorkEntry]) -> DerivedExperience {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let currentYear = now.year ?? 2025
        let currentMonth = now.month ?? 1

        // Total software years: span from earliest start to latest end/present
        let totalYears = computeSpanYears(entries, currentYear: currentYear, currentMonth: currentMonth)

        // iOS years: roles where title or bullets suggest iOS work
        let iosYears = computeIOSYears(entries, currentYear: currentYear, currentMonth: currentMonth)

        // International experience: roles in non-Japanese locations or with international keywords
        let hasInternational = detectInternationalExperience(entries)

        // JP work years: roles located in Japan
        let jpYears = computeJPWorkYears(entries, currentYear: currentYear, currentMonth: currentMonth)

        return DerivedExperience(
            totalSoftwareYears: totalYears,
            iosYears: iosYears,
            hasInternationalTeamExperience: hasInternational,
            jpWorkYears: jpYears
        )
    }

    /// Total years from earliest professional start date to latest/current role end.
    static func computeSpanYears(
        _ entries: [NormalizedWorkEntry],
        currentYear: Int,
        currentMonth: Int
    ) -> Int {
        guard let earliest = entries.compactMap({ $0.startDate }).min() else { return 0 }

        let latestYear: Int
        let latestMonth: Int

        if entries.contains(where: { $0.isCurrent }) {
            latestYear = currentYear
            latestMonth = currentMonth
        } else if let latest = entries.compactMap({ $0.endDate }).max() {
            latestYear = latest.year
            latestMonth = latest.month ?? 12
        } else {
            latestYear = currentYear
            latestMonth = currentMonth
        }

        let startMonth = earliest.month ?? 1
        let totalMonths = (latestYear - earliest.year) * 12 + (latestMonth - startMonth)
        return max(0, totalMonths / 12)
    }

    // MARK: - iOS years detection

    private static let iosKeywords: Set<String> = [
        "ios", "iphone", "ipad", "swift", "swiftui", "uikit", "objective-c",
        "objc", "xcode", "cocoapods", "mobile app", "apple"
    ]

    static func computeIOSYears(
        _ entries: [NormalizedWorkEntry],
        currentYear: Int,
        currentMonth: Int
    ) -> Int? {
        var iosMonths = 0

        for entry in entries {
            guard isIOSRole(entry) else { continue }
            guard let start = entry.startDate else { continue }

            let endYear: Int
            let endMonth: Int
            if entry.isCurrent || entry.endDate == nil {
                endYear = currentYear
                endMonth = currentMonth
            } else if let end = entry.endDate {
                endYear = end.year
                endMonth = end.month ?? 12
            } else {
                continue
            }

            let months = (endYear - start.year) * 12 + (endMonth - (start.month ?? 1))
            if months > 0 { iosMonths += months }
        }

        return iosMonths > 0 ? iosMonths / 12 : nil
    }

    static func isIOSRole(_ entry: NormalizedWorkEntry) -> Bool {
        let titleLower = (entry.title ?? "").lowercased()
        let bulletTexts = entry.bullets.map { $0.text.lowercased() }
        let allText = titleLower + " " + bulletTexts.joined(separator: " ")

        return iosKeywords.contains { allText.contains($0) }
    }

    // MARK: - International experience detection

    private static let internationalKeywords: Set<String> = [
        "international", "global", "cross-border", "remote", "distributed",
        "multi-country", "overseas", "multinational"
    ]

    private static let japanLocations: Set<String> = [
        "japan", "tokyo", "osaka", "kyoto", "yokohama", "fukuoka", "nagoya",
        "sapporo", "kobe", "東京", "大阪", "京都", "福岡", "名古屋", "日本"
    ]

    static func detectInternationalExperience(_ entries: [NormalizedWorkEntry]) -> Bool {
        let locations = Set(entries.compactMap { $0.location?.lowercased() })

        // Multiple distinct countries/regions suggest international experience
        let hasJapanRole = locations.contains { loc in
            japanLocations.contains { loc.contains($0) }
        }
        let hasNonJapanRole = locations.contains { loc in
            !japanLocations.contains { loc.contains($0) } && !loc.isEmpty
        }
        if hasJapanRole && hasNonJapanRole { return true }

        // Check bullet text for international keywords
        for entry in entries {
            let allText = (entry.bullets.map { $0.text } + [entry.title ?? ""]).joined(separator: " ").lowercased()
            if internationalKeywords.contains(where: { allText.contains($0) }) {
                return true
            }
        }

        return false
    }

    // MARK: - Japan work years

    static func computeJPWorkYears(
        _ entries: [NormalizedWorkEntry],
        currentYear: Int,
        currentMonth: Int
    ) -> Int? {
        var jpMonths = 0

        for entry in entries {
            guard isJapanRole(entry) else { continue }
            guard let start = entry.startDate else { continue }

            let endYear: Int
            let endMonth: Int
            if entry.isCurrent || entry.endDate == nil {
                endYear = currentYear
                endMonth = currentMonth
            } else if let end = entry.endDate {
                endYear = end.year
                endMonth = end.month ?? 12
            } else {
                continue
            }

            let months = (endYear - start.year) * 12 + (endMonth - (start.month ?? 1))
            if months > 0 { jpMonths += months }
        }

        return jpMonths > 0 ? jpMonths / 12 : nil
    }

    static func isJapanRole(_ entry: NormalizedWorkEntry) -> Bool {
        guard let location = entry.location?.lowercased() else { return false }
        return japanLocations.contains { location.contains($0) }
    }

    // MARK: - Formatting helpers

    private static func formatDate(_ date: StructuredDate) -> String {
        if let month = date.month {
            return "\(date.year)/\(String(format: "%02d", month))"
        }
        return "\(date.year)"
    }
}
