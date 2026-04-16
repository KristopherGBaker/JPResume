import Foundation

enum MarkdownParser {
    static func parse(_ text: String) -> WesternResume {
        let sections = splitSections(text)
        var resume = WesternResume()

        resume.name = extractName(text)

        let header = sections["_header"] ?? ""
        resume.contact = extractContact(header)

        for (heading, content) in sections where heading != "_header" {
            guard let category = SectionClassifier.classify(heading) else {
                resume.rawSections[heading] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }
            switch category {
            case .summary:
                resume.summary = content.trimmingCharacters(in: .whitespacesAndNewlines)
            case .experience:
                resume.experience = parseExperience(content)
            case .education:
                resume.education = parseEducation(content)
            case .skills:
                resume.skills = parseSkills(content)
            case .certifications:
                resume.certifications = parseListItems(content)
            case .languages:
                resume.languages = parseListItems(content)
            default:
                resume.rawSections[heading] = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return resume
    }

    // MARK: - Name Extraction

    static func extractName(_ text: String) -> String? {
        // Try H1 first
        if let match = regex(#"^#\s+(.+)$"#, options: .anchorsMatchLines).firstMatch(in: text) {
            return match.group(1)?.trimmingCharacters(in: .whitespaces)
        }
        // Try standalone bold line
        if let match = regex(#"^\*\*([^*]+)\*\*\s*$"#, options: .anchorsMatchLines).firstMatch(in: text) {
            return match.group(1)?.trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    // MARK: - Section Splitting

    static func splitSections(_ text: String) -> [String: String] {
        var sections: [String: String] = [:]

        // Try H2 headings
        let h2Regex = regex(#"^##\s+(.+)$"#, options: .anchorsMatchLines)
        let h2Matches = h2Regex.allMatches(in: text)

        if !h2Matches.isEmpty {
            sections["_header"] = String(text[text.startIndex..<h2Matches[0].range.lowerBound])
            for (i, match) in h2Matches.enumerated() {
                let heading = match.group(1)!.trimmingCharacters(in: .whitespaces)
                let contentStart = match.range.upperBound
                let contentEnd = i + 1 < h2Matches.count
                    ? h2Matches[i + 1].range.lowerBound
                    : text.endIndex
                sections[heading] = String(text[contentStart..<contentEnd])
            }
            return sections
        }

        // Try standalone bold lines as section headings
        let boldRegex = regex(#"^(\*\*[A-Z][A-Z &]+\*\*)\s*$"#, options: .anchorsMatchLines)
        let boldMatches = boldRegex.allMatches(in: text)

        if !boldMatches.isEmpty {
            sections["_header"] = String(text[text.startIndex..<boldMatches[0].range.upperBound])

            var sectionMatches: [RegexMatch] = []
            for m in boldMatches {
                let heading = m.group(1)!
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                if SectionClassifier.classify(heading) != nil {
                    sectionMatches.append(m)
                }
            }
            if sectionMatches.isEmpty {
                sectionMatches = Array(boldMatches.dropFirst())
            }

            for (i, m) in sectionMatches.enumerated() {
                let heading = m.group(1)!
                    .trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "**", with: "")
                let contentStart = m.range.upperBound
                let contentEnd = i + 1 < sectionMatches.count
                    ? sectionMatches[i + 1].range.lowerBound
                    : text.endIndex
                sections[heading] = String(text[contentStart..<contentEnd])
            }
            return sections
        }

        sections["_header"] = text
        return sections
    }

    // MARK: - Contact Extraction

    static func extractContact(_ header: String) -> ContactInfo {
        var contact = ContactInfo()

        if let match = regex(#"[\w.+\-]+@[\w\-]+\.[\w.\-]+"#).firstMatch(in: header) {
            contact.email = match.group(0)
        }
        if let match = regex(#"[+]?[\d\s\-().]{7,15}"#).firstMatch(in: header) {
            let phone = match.group(0)!.trimmingCharacters(in: .whitespaces)
            let digits = phone.replacingOccurrences(of: #"[\s\-().+]"#, with: "", options: .regularExpression)
            if digits.count >= 7 {
                contact.phone = phone
            }
        }
        if let match = regex(#"(?:linkedin\.com/in/|linkedin:\s*)(\S+)"#, options: .caseInsensitive).firstMatch(in: header) {
            contact.linkedin = match.group(1)?.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        }
        if let match = regex(#"(?:github\.com/|github:\s*)(\S+)"#, options: .caseInsensitive).firstMatch(in: header) {
            contact.github = match.group(1)?.trimmingCharacters(in: CharacterSet(charactersIn: ")"))
        }
        return contact
    }

    // MARK: - Experience Parsing

    static func parseExperience(_ content: String) -> [WorkEntry] {
        var entries: [WorkEntry] = []

        // Try H3 headings
        let h3Regex = regex(#"^###\s+(.+)$"#, options: .anchorsMatchLines)
        let h3Matches = h3Regex.allMatches(in: content)

        if !h3Matches.isEmpty {
            for (i, match) in h3Matches.enumerated() {
                let heading = match.group(1)!.trimmingCharacters(in: .whitespaces)
                let blockStart = match.range.upperBound
                let blockEnd = i + 1 < h3Matches.count
                    ? h3Matches[i + 1].range.lowerBound
                    : content.endIndex
                let block = String(content[blockStart..<blockEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(parseWorkBlock(heading: heading, block: block))
            }
            return entries
        }

        // Try bold heading pattern: **Company** | Title
        let boldEntryRegex = regex(#"^\*\*(.+?)\*\*\s*(?:\|\s*(.+))?$"#, options: .anchorsMatchLines)
        let boldMatches = boldEntryRegex.allMatches(in: content)

        if !boldMatches.isEmpty {
            for (i, match) in boldMatches.enumerated() {
                let company = match.group(1)!.trimmingCharacters(in: .whitespaces)
                let title = match.group(2)?.trimmingCharacters(in: .whitespaces)
                let blockStart = match.range.upperBound
                let blockEnd = i + 1 < boldMatches.count
                    ? boldMatches[i + 1].range.lowerBound
                    : content.endIndex
                let block = String(content[blockStart..<blockEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(parseWorkBlockMultiline(company: company, title: title, block: block))
            }
            return entries
        }

        return entries
    }

    static func parseWorkBlock(heading: String, block: String) -> WorkEntry {
        var entry = WorkEntry(company: heading)

        let parts = heading.components(separatedBy: " | ")
        if parts.count >= 2 {
            entry.company = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
            entry.title = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
        }
        if parts.count >= 3 {
            let (start, end) = parseDateRange(parts[2])
            entry.startDate = start
            entry.endDate = end
        }

        if entry.startDate == nil {
            extractDates(from: block, into: &entry)
        }
        entry.bullets = parseListItems(block)
        return entry
    }

    static func parseWorkBlockMultiline(company: String, title: String?, block: String) -> WorkEntry {
        var entry = WorkEntry(company: company, title: title)
        extractDates(from: block, into: &entry)

        // Extract location
        let dateLocRegex = regex(#"(?:\w+\.?\s+\d{4})\s*[-–—]+\s*(?:\w+\.?\s+\d{4}|[Pp]resent|[Cc]urrent)\s*\|\s*(.+)"#)
        if let match = dateLocRegex.firstMatch(in: block) {
            entry.location = match.group(1)?.trimmingCharacters(in: .whitespaces)
        }

        entry.bullets = parseListItems(block)
        return entry
    }

    static func extractDates(from block: String, into entry: inout WorkEntry) {
        let dateRegex = regex(#"(\w+\.?\s+\d{4})\s*[-–—]+\s*(\w+\.?\s+\d{4}|[Pp]resent|[Cc]urrent)"#)
        if let match = dateRegex.firstMatch(in: block) {
            entry.startDate = match.group(1)
            entry.endDate = match.group(2)
        }
    }

    static func parseDateRange(_ text: String) -> (String?, String?) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let parts = trimmed.components(separatedBy: regex(#"\s*[-–—]\s*|\s+to\s+"#))
        if parts.count == 2 {
            return (parts[0].trimmingCharacters(in: .whitespaces),
                    parts[1].trimmingCharacters(in: .whitespaces))
        }
        if parts.count == 1 && !parts[0].isEmpty {
            return (parts[0].trimmingCharacters(in: .whitespaces), nil)
        }
        return (nil, nil)
    }

    // MARK: - Education Parsing

    static func parseEducation(_ content: String) -> [EducationEntry] {
        var entries: [EducationEntry] = []

        let h3Regex = regex(#"^###\s+(.+)$"#, options: .anchorsMatchLines)
        let h3Matches = h3Regex.allMatches(in: content)

        if !h3Matches.isEmpty {
            for (i, match) in h3Matches.enumerated() {
                let heading = match.group(1)!.trimmingCharacters(in: .whitespaces)
                let blockStart = match.range.upperBound
                let blockEnd = i + 1 < h3Matches.count
                    ? h3Matches[i + 1].range.lowerBound
                    : content.endIndex
                let block = String(content[blockStart..<blockEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(parseEducationBlock(heading: heading, block: block))
            }
            return entries
        }

        // Try bold headings
        let boldRegex = regex(#"^\*\*(.+?)\*\*\s*(?:\|\s*(.+))?$"#, options: .anchorsMatchLines)
        let boldMatches = boldRegex.allMatches(in: content)

        if !boldMatches.isEmpty {
            for (i, match) in boldMatches.enumerated() {
                var heading = match.group(1)!.trimmingCharacters(in: .whitespaces)
                if let extra = match.group(2) {
                    heading += " | " + extra.trimmingCharacters(in: .whitespaces)
                }
                let blockStart = match.range.upperBound
                let blockEnd = i + 1 < boldMatches.count
                    ? boldMatches[i + 1].range.lowerBound
                    : content.endIndex
                let block = String(content[blockStart..<blockEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
                entries.append(parseEducationBlock(heading: heading, block: block))
            }
        }

        return entries
    }

    static func parseEducationBlock(heading: String, block: String) -> EducationEntry {
        var entry = EducationEntry(institution: heading)

        let parts = heading.components(separatedBy: " | ")
        if parts.count >= 1 {
            entry.institution = parts[0].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
        }
        if parts.count >= 2 {
            entry.degree = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "*", with: "")
        }
        if parts.count >= 3 {
            entry.graduationDate = parts[2].trimmingCharacters(in: .whitespaces)
        }

        // Look for degree in block
        if entry.degree == nil {
            let degreeRegex = regex(#"((?:B\.?S\.?|M\.?S\.?|Ph\.?D\.?|B\.?A\.?|M\.?A\.?|MBA|Bachelor|Master|Doctor)\w*(?:\s+(?:of|in)\s+\w[\w\s,]*)?)"#, options: .caseInsensitive)
            if let match = degreeRegex.firstMatch(in: block) {
                entry.degree = match.group(1)?.trimmingCharacters(in: .whitespaces)
            }
        }

        // Look for date
        if entry.graduationDate == nil {
            if let match = regex(#"(\d{4})"#).firstMatch(in: block) {
                entry.graduationDate = match.group(1)
            }
        }

        // Look for GPA
        if let match = regex(#"GPA:?\s*([\d.]+)"#, options: .caseInsensitive).firstMatch(in: block) {
            entry.gpa = match.group(1)
        }

        return entry
    }

    // MARK: - Skills Parsing

    static func parseSkills(_ content: String) -> [String] {
        var skills: [String] = []

        for line in content.split(separator: "\n") {
            var cleaned = String(line).trimmingCharacters(in: .whitespaces)
            if cleaned.isEmpty { continue }

            // Remove bold category labels
            cleaned = cleaned.replacingOccurrences(
                of: #"^\*\*[^*]+:\*\*\s*"#, with: "", options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^\*\*[^*]+\*\*:?\s*"#, with: "", options: .regularExpression
            )
            // Remove bullet markers
            cleaned = cleaned.replacingOccurrences(
                of: #"^[-•]\s+"#, with: "", options: .regularExpression
            )
            cleaned = cleaned.replacingOccurrences(
                of: #"^\*\s+(?!\*)"#, with: "", options: .regularExpression
            )
            // Remove non-bold category labels
            if cleaned.contains(":") {
                let beforeColon = cleaned.components(separatedBy: ":").first ?? ""
                if !beforeColon.contains(where: { ",;|".contains($0) }) {
                    cleaned = cleaned.replacingOccurrences(
                        of: #"^[A-Za-z\s]+:\s*"#, with: "", options: .regularExpression
                    )
                }
            }

            if cleaned.isEmpty { continue }

            for skill in cleaned.components(separatedBy: regex(#"\s*[,;|]\s*"#)) {
                let trimmed = skill.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty && trimmed.count > 1 {
                    skills.append(trimmed)
                }
            }
        }
        return skills
    }

    // MARK: - List Items

    static func parseListItems(_ content: String) -> [String] {
        var items: [String] = []
        for line in content.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            let bulletRegex = regex(#"^[-*•]\s+(.+)$"#)
            if let match = bulletRegex.firstMatch(in: trimmed) {
                items.append(match.group(1)!.trimmingCharacters(in: .whitespaces))
            }
        }
        return items
    }
}

// MARK: - Regex Helpers

private struct RegexMatch {
    let range: Range<String.Index>
    private let text: String
    private let result: NSTextCheckingResult

    init(text: String, result: NSTextCheckingResult) {
        self.text = text
        self.result = result
        let nsRange = result.range
        let start = text.index(text.startIndex, offsetBy: nsRange.location)
        let end = text.index(start, offsetBy: nsRange.length)
        self.range = start..<end
    }

    func group(_ index: Int) -> String? {
        let nsRange = result.range(at: index)
        guard nsRange.location != NSNotFound else { return nil }
        let start = text.index(text.startIndex, offsetBy: nsRange.location)
        let end = text.index(start, offsetBy: nsRange.length)
        return String(text[start..<end])
    }
}

private struct RegexWrapper {
    let nsRegex: NSRegularExpression

    func firstMatch(in text: String) -> RegexMatch? {
        let range = NSRange(text.startIndex..., in: text)
        guard let result = nsRegex.firstMatch(in: text, range: range) else { return nil }
        return RegexMatch(text: text, result: result)
    }

    func allMatches(in text: String) -> [RegexMatch] {
        let range = NSRange(text.startIndex..., in: text)
        return nsRegex.matches(in: text, range: range).map { RegexMatch(text: text, result: $0) }
    }
}

private func regex(_ pattern: String, options: NSRegularExpression.Options = []) -> RegexWrapper {
    RegexWrapper(nsRegex: try! NSRegularExpression(pattern: pattern, options: options))
}

extension String {
    fileprivate func components(separatedBy wrapper: RegexWrapper) -> [String] {
        let range = NSRange(startIndex..., in: self)
        var parts: [String] = []
        var lastEnd = startIndex
        for match in wrapper.nsRegex.matches(in: self, range: range) {
            let matchStart = index(startIndex, offsetBy: match.range.location)
            parts.append(String(self[lastEnd..<matchStart]))
            lastEnd = index(matchStart, offsetBy: match.range.length)
        }
        parts.append(String(self[lastEnd...]))
        return parts
    }
}
