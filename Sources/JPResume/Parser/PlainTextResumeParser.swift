import Foundation

enum PlainTextResumeParser {
    static func parse(_ text: String) -> WesternResume {
        let sections = splitSections(text)
        var resume = WesternResume()

        resume.name = extractName(text)
        let header = sections["_header"] ?? ""
        resume.contact = MarkdownParser.extractContact(header)

        for (heading, content) in sections where heading != "_header" {
            guard let category = SectionClassifier.classify(heading) else {
                resume.rawSections[heading] = content.trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            switch category {
            case .summary:
                resume.summary = normalizeParagraphs(content)
            case .experience:
                resume.experience = parseExperience(content)
            case .education:
                resume.education = parseEducation(content)
            case .skills:
                resume.skills = parseSkills(content)
            case .certifications:
                resume.certifications = parseSimpleItems(content)
            case .languages:
                resume.languages = parseSimpleItems(content)
            case .projects:
                resume.rawSections[heading] = normalizeProjectSection(content)
            default:
                resume.rawSections[heading] = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return resume
    }

    private static func extractName(_ text: String) -> String? {
        if let markdownName = MarkdownParser.extractName(text) {
            return markdownName
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains("@") || line.contains("|") { continue }
            if SectionClassifier.classify(line) != nil { continue }
            let words = line.split(separator: " ")
            if words.count <= 5, line.rangeOfCharacter(from: .letters) != nil {
                return line
            }
        }
        return nil
    }

    private static func splitSections(_ text: String) -> [String: String] {
        let lines = text.components(separatedBy: "\n")
        var sectionStarts: [(heading: String, index: Int)] = []

        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let heading = normalizedHeading(from: line) else { continue }
            sectionStarts.append((heading, index))
        }

        guard !sectionStarts.isEmpty else {
            return ["_header": text]
        }

        var sections: [String: String] = [:]
        sections["_header"] = lines[..<sectionStarts[0].index].joined(separator: "\n")

        for (position, section) in sectionStarts.enumerated() {
            let start = section.index + 1
            let end = position + 1 < sectionStarts.count ? sectionStarts[position + 1].index : lines.count
            sections[section.heading] = lines[start..<end].joined(separator: "\n")
        }

        return sections
    }

    private static func normalizedHeading(from line: String) -> String? {
        guard !line.isEmpty, !line.contains("|"), line.count <= 40 else { return nil }
        if let category = SectionClassifier.classify(line) {
            return category.rawValue.capitalized
        }

        let stripped = line.replacingOccurrences(of: #"[^\p{L}\p{N}& /]"#, with: "", options: .regularExpression)
        if stripped == line, isLikelyHeading(line), let category = SectionClassifier.classify(line.lowercased()) {
            return category.rawValue.capitalized
        }
        return nil
    }

    private static func isLikelyHeading(_ line: String) -> Bool {
        let letters = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        let uppercase = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        return uppercase.count == letters.count || line == line.uppercased()
    }

    private static func parseExperience(_ content: String) -> [WorkEntry] {
        let lines = content.components(separatedBy: "\n")
        var entries: [WorkEntry] = []
        var index = 0

        while index < lines.count {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard isExperienceHeading(line, nextLines: Array(lines.dropFirst(index + 1).prefix(2))) else {
                index += 1
                continue
            }

            var entry = workEntry(from: line)
            index += 1

            while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
            }

            if index < lines.count {
                let dateLocation = lines[index].trimmingCharacters(in: .whitespaces)
                if looksLikeDateLine(dateLocation) {
                    applyDateLine(dateLocation, to: &entry)
                    index += 1
                }
            }

            let blockStart = index
            while index < lines.count {
                let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                if isExperienceHeading(candidate, nextLines: Array(lines.dropFirst(index + 1).prefix(2))) {
                    break
                }
                index += 1
            }
            let block = lines[blockStart..<index].joined(separator: "\n")
            entry.bullets = parseBulletParagraphs(block)
            entries.append(entry)
        }

        return entries
    }

    private static func parseEducation(_ content: String) -> [EducationEntry] {
        let lines = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return [] }

        var entries: [EducationEntry] = []
        var current: [String] = []

        for line in lines {
            if isEducationHeading(line), !current.isEmpty {
                entries.append(parseEducationBlock(current))
                current = [line]
            } else {
                current.append(line)
            }
        }

        if !current.isEmpty {
            entries.append(parseEducationBlock(current))
        }

        return entries
    }

    private static func parseEducationBlock(_ lines: [String]) -> EducationEntry {
        var entry = EducationEntry(institution: lines.first ?? "")

        for line in lines.dropFirst() {
            if entry.degree == nil, looksLikeDegreeLine(line) {
                entry.degree = line
                continue
            }
            if entry.graduationDate == nil,
               let match = plainRegex(#"(?<!\d)(\d{4})(?!\d)"#).firstMatch(in: line) {
                entry.graduationDate = match.group(1)
            }
            if entry.gpa == nil,
               let match = plainRegex(#"GPA:?\s*([\d.]+)"#, options: .caseInsensitive).firstMatch(in: line) {
                entry.gpa = match.group(1)
            }
        }

        return entry
    }

    private static func parseSimpleItems(_ content: String) -> [String] {
        let bullets = parseBulletParagraphs(content)
        if !bullets.isEmpty { return bullets }
        return content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private static func parseSkills(_ content: String) -> [String] {
        var skills: [String] = []
        for rawLine in content.components(separatedBy: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if let colon = line.firstIndex(of: ":") {
                let label = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                if label.range(of: #"^[A-Za-z& /\-]+$"#, options: .regularExpression) != nil {
                    line = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                }
            }

            for skill in splitDelimitedSkills(line) {
                let trimmed = skill.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    skills.append(trimmed)
                }
            }
        }
        return skills
    }

    private static func splitDelimitedSkills(_ line: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var parenDepth = 0

        for char in line {
            switch char {
            case "(":
                parenDepth += 1
                current.append(char)
            case ")":
                parenDepth = max(0, parenDepth - 1)
                current.append(char)
            case "," where parenDepth == 0:
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
                current = ""
            case ";" where parenDepth == 0:
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty {
                    parts.append(trimmed)
                }
                current = ""
            default:
                current.append(char)
            }
        }

        let trailing = current.trimmingCharacters(in: .whitespaces)
        if !trailing.isEmpty {
            parts.append(trailing)
        }
        return parts
    }

    private static func normalizeParagraphs(_ content: String) -> String {
        content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func normalizeProjectSection(_ content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        let bullets = parseBulletParagraphs(content)
        if bullets.isEmpty {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var prefix: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("•") || trimmed.hasPrefix("●") || trimmed.hasPrefix("-") || trimmed.hasPrefix("*") {
                break
            }
            prefix.append(trimmed)
        }

        var sections = prefix.filter { !$0.isEmpty }
        sections.append(contentsOf: bullets.map { "• \($0)" })
        return sections.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isExperienceHeading(_ line: String, nextLines: [String]) -> Bool {
        guard line.contains(" | "), !line.hasPrefix("•"), !line.hasPrefix("-"), !line.hasPrefix("*") else {
            return false
        }
        if nextLines.contains(where: { looksLikeDateLine($0.trimmingCharacters(in: .whitespaces)) }) {
            return true
        }
        let parts = line.components(separatedBy: " | ")
        return parts.count >= 2 && parts[0].count < 80
    }

    private static func workEntry(from heading: String) -> WorkEntry {
        let parts = heading.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        let company = parts.first ?? heading
        let title = parts.count >= 2 ? parts[1] : nil
        return WorkEntry(company: company, title: title)
    }

    private static func looksLikeDateLine(_ line: String) -> Bool {
        line.range(of: #"\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|January|February|March|April|June|July|August|September|October|November|December)\b.*[–—-].*(?:Present|Current|Now|\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|January|February|March|April|June|July|August|September|October|November|December)\b)"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func applyDateLine(_ line: String, to entry: inout WorkEntry) {
        let parts = line.components(separatedBy: " | ").map { $0.trimmingCharacters(in: .whitespaces) }
        let datePart = parts.first ?? line
        let rangeParts = datePart.components(separatedBy: plainRegex(#"\s*[-–—]\s*"#))
        if rangeParts.count >= 2 {
            entry.startDate = rangeParts[0].trimmingCharacters(in: CharacterSet.whitespaces)
            entry.endDate = rangeParts[1].trimmingCharacters(in: CharacterSet.whitespaces)
        }
        if parts.count >= 2 {
            entry.location = parts[1]
        }
    }

    private static func parseBulletParagraphs(_ content: String) -> [String] {
        let lines = content.components(separatedBy: "\n")
        var bullets: [String] = []
        var current: String?

        func flush() {
            if let current, !current.isEmpty {
                bullets.append(current.trimmingCharacters(in: .whitespaces))
            }
            current = nil
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
                continue
            }

            if line.range(of: #"^(?:[-*•●])\s*(.*)$"#, options: .regularExpression) != nil {
                flush()
                let stripped = line.replacingOccurrences(of: #"^(?:[-*•●])\s*"#, with: "", options: .regularExpression)
                if !stripped.isEmpty {
                    current = stripped
                }
            } else if current != nil {
                current = current! + " " + line
            }
        }

        flush()
        return bullets
    }

    private static func isEducationHeading(_ line: String) -> Bool {
        if line.hasPrefix("•") || line.hasPrefix("-") || line.hasPrefix("*") { return false }
        if SectionClassifier.classify(line) != nil { return false }
        return line.range(of: #"(University|College|School|Institute|Academy)"#, options: [.regularExpression, .caseInsensitive]) != nil
            || line.contains("大学")
            || line.contains("高校")
    }

    private static func looksLikeDegreeLine(_ line: String) -> Bool {
        if line.contains("|") { return true }
        return line.range(
            of: #"(Bachelor|Master|B\.?S\.?|M\.?S\.?|Ph\.?D\.?|Computer Science|Mathematics|Engineering|Science|Arts|Minor|Major)"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

private struct PlainRegexMatch {
    let text: String
    let result: NSTextCheckingResult

    func group(_ index: Int) -> String? {
        let nsRange = result.range(at: index)
        guard nsRange.location != NSNotFound,
              let range = Range(nsRange, in: text) else { return nil }
        return String(text[range])
    }
}

private struct PlainRegexWrapper {
    let regex: NSRegularExpression

    func firstMatch(in text: String) -> PlainRegexMatch? {
        let range = NSRange(text.startIndex..., in: text)
        guard let result = regex.firstMatch(in: text, range: range) else { return nil }
        return PlainRegexMatch(text: text, result: result)
    }
}

private func plainRegex(_ pattern: String, options: NSRegularExpression.Options = []) -> PlainRegexWrapper {
    PlainRegexWrapper(regex: try! NSRegularExpression(pattern: pattern, options: options))
}

private extension String {
    func components(separatedBy wrapper: PlainRegexWrapper) -> [String] {
        let range = NSRange(startIndex..., in: self)
        var parts: [String] = []
        var lastEnd = startIndex
        for match in wrapper.regex.matches(in: self, range: range) {
            guard let matchRange = Range(match.range, in: self) else { continue }
            parts.append(String(self[lastEnd..<matchRange.lowerBound]))
            lastEnd = matchRange.upperBound
        }
        parts.append(String(self[lastEnd...]))
        return parts
    }
}
