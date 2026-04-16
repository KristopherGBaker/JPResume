import Foundation

// MARK: - Validation types

enum ValidationSeverity: Sendable {
    case warning, error
}

struct ValidationIssue: Sendable {
    let severity: ValidationSeverity
    let field: String
    let message: String
}

struct ValidationResult: Sendable {
    let issues: [ValidationIssue]
    let totalYearsExperience: Double?

    var warnings: [ValidationIssue] { issues.filter { $0.severity == .warning } }
    var errors: [ValidationIssue] { issues.filter { $0.severity == .error } }
    var isValid: Bool { errors.isEmpty }
    var hasIssues: Bool { !issues.isEmpty }

    init(issues: [ValidationIssue], totalYearsExperience: Double? = nil) {
        self.issues = issues
        self.totalYearsExperience = totalYearsExperience
    }
}

// MARK: - Validator

enum ResumeValidator {
    static func validate(_ resume: NormalizedResume) -> ValidationResult {
        var issues: [ValidationIssue] = []

        // Required fields
        if resume.name == nil || resume.name?.isEmpty == true {
            issues.append(.init(severity: .warning, field: "name", message: "Name is missing"))
        }
        if resume.experience.isEmpty {
            issues.append(.init(severity: .warning, field: "experience",
                                message: "No work experience entries found"))
        }
        if resume.education.isEmpty {
            issues.append(.init(severity: .warning, field: "education",
                                message: "No education entries found"))
        }

        // Work entry checks
        for (i, entry) in resume.experience.enumerated() {
            let label = "\(entry.company) (\(entry.title ?? "unknown title"))"

            // start <= end
            if let start = entry.startDate, let end = entry.endDate, start > end {
                issues.append(.init(
                    severity: .warning,
                    field: "experience[\(i)]",
                    message: "\(label): start date \(formatDate(start)) is after end date \(formatDate(end))"
                ))
            }

            // isCurrent consistency
            if entry.isCurrent && entry.endDate != nil {
                issues.append(.init(
                    severity: .warning,
                    field: "experience[\(i)]",
                    message: "\(label): marked as current but has an end date"
                ))
            }

            // Low confidence
            if let confidence = entry.confidence, confidence < 0.6 {
                issues.append(.init(
                    severity: .warning,
                    field: "experience[\(i)]",
                    message: "\(label): low normalization confidence (\(String(format: "%.0f%%", confidence * 100)))"
                ))
            }
        }

        // Overlapping work entries
        let sortedWork = resume.experience
            .filter { $0.startDate != nil }
            .sorted { ($0.startDate ?? StructuredDate(year: 0)) < ($1.startDate ?? StructuredDate(year: 0)) }
        for i in 0..<sortedWork.count {
            for j in (i + 1)..<sortedWork.count {
                let a = sortedWork[i]
                let b = sortedWork[j]
                guard a.startDate != nil, let bStart = b.startDate else { continue }
                let aEnd = a.isCurrent ? nil : a.endDate
                guard let aEndDate = aEnd else { continue } // current role can overlap
                // Only warn when the overlap is unambiguous:
                // bStart is strictly before aEnd by year, OR both have months and bStart < aEnd.
                let clearOverlap: Bool
                if bStart.year < aEndDate.year {
                    clearOverlap = true
                } else if bStart.year == aEndDate.year,
                          let bMonth = bStart.month, let aMonth = aEndDate.month {
                    clearOverlap = bMonth < aMonth
                } else {
                    clearOverlap = false
                }
                if clearOverlap {
                    issues.append(.init(
                        severity: .warning,
                        field: "experience",
                        message: "Overlapping roles: \(a.company) and \(b.company) — check dates"
                    ))
                }
            }
        }

        // Education entry checks
        for (i, entry) in resume.education.enumerated() {
            if let start = entry.startDate, let grad = entry.graduationDate, start > grad {
                issues.append(.init(
                    severity: .warning,
                    field: "education[\(i)]",
                    message: "\(entry.institution): start date is after graduation date"
                ))
            }
            if let confidence = entry.confidence, confidence < 0.6 {
                issues.append(.init(
                    severity: .warning,
                    field: "education[\(i)]",
                    message: "\(entry.institution): low normalization confidence (\(String(format: "%.0f%%", confidence * 100)))"
                ))
            }
        }

        // Skill categorization quality
        if !resume.skillCategories.isEmpty {
            let allInOther = resume.skillCategories.count == 1
                && resume.skillCategories[0].name.lowercased() == "other"
            if allInOther {
                issues.append(.init(
                    severity: .warning,
                    field: "skill_categories",
                    message: "All skills landed in 'Other' — categorization may have failed"
                ))
            }
        }

        // Total years of experience
        let totalYears = computeTotalYears(resume.experience)

        return ValidationResult(issues: issues, totalYearsExperience: totalYears)
    }

    // MARK: - Console output

    static func printResult(_ result: ValidationResult, verbose: Bool = false) {
        if let years = result.totalYearsExperience {
            print("  Total experience: \(String(format: "%.1f", years)) years")
        }
        for issue in result.issues {
            switch issue.severity {
            case .warning:
                print("  ⚠️  \(issue.field): \(issue.message)")
            case .error:
                print("  ✘  \(issue.field): \(issue.message)")
            }
        }
    }

    // MARK: - Private helpers

    private static func computeTotalYears(_ entries: [NormalizedWorkEntry]) -> Double? {
        let now = Calendar.current.dateComponents([.year, .month], from: Date())
        let currentYear = now.year ?? 2025
        let currentMonth = now.month ?? 1

        var totalMonths = 0
        for entry in entries {
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
            let startMonth = start.month ?? 1
            let months = (endYear - start.year) * 12 + (endMonth - startMonth)
            if months > 0 { totalMonths += months }
        }

        return totalMonths > 0 ? Double(totalMonths) / 12.0 : nil
    }

    private static func formatDate(_ date: StructuredDate) -> String {
        if let month = date.month {
            return "\(date.year)/\(String(format: "%02d", month))"
        }
        return "\(date.year)"
    }
}
