import Foundation

enum InteractivePrompter {

    // MARK: - Main Flow

    static func promptAll(western: WesternResume) -> JapanConfig {
        var config = JapanConfig()

        // Personal Information
        printHeader("Personal Information")
        config.nameKanji = prompt("  Full name in kanji")
        config.nameFurigana = prompt("  Full name in furigana (katakana)")

        let dobStr = prompt("  Date of birth (YYYY-MM-DD)")
        if !dobStr.isEmpty {
            config.dateOfBirth = dobStr
        }

        let gender = prompt("  Gender (optional, Enter to skip)", default: "")
        config.gender = gender.isEmpty ? nil : gender

        // Address
        printHeader("Address")
        var addr = JapaneseAddress()
        addr.postalCode = prompt("  Postal code (〒XXX-XXXX)")
        print("  Prefectures: \(Prefectures.all.prefix(5).joined(separator: ", "))...")
        addr.prefecture = prompt("  Prefecture (都道府県)")
        addr.city = prompt("  City/Ward (市区町村)")
        addr.line1 = prompt("  Address line 1")
        let line2 = prompt("  Address line 2 (optional, Enter to skip)", default: "")
        addr.line2 = line2.isEmpty ? nil : line2
        addr.furigana = prompt("  Address furigana")
        config.addressCurrent = addr

        if confirm("  Different contact address?", default: false) {
            printHeader("Contact Address")
            var caddr = JapaneseAddress()
            caddr.postalCode = prompt("  Contact postal code")
            caddr.prefecture = prompt("  Contact prefecture")
            caddr.city = prompt("  Contact city")
            caddr.line1 = prompt("  Contact address line 1")
            let cl2 = prompt("  Contact address line 2 (optional)", default: "")
            caddr.line2 = cl2.isEmpty ? nil : cl2
            caddr.furigana = prompt("  Contact address furigana")
            config.addressContact = caddr
        }

        // Contact
        printHeader("Contact")
        config.phone = prompt("  Phone number", default: western.contact.phone ?? "")
        config.email = prompt("  Email", default: western.contact.email ?? "")

        let photo = prompt("  Photo path (optional, Enter to skip)", default: "")
        config.photoPath = photo.isEmpty ? nil : photo

        // Additional
        printHeader("Additional")
        let commute = prompt("  Commute time (e.g. 約45分, Enter to skip)", default: "")
        config.commuteTime = commute.isEmpty ? nil : commute

        let spouse = prompt("  Spouse? (yes/no, Enter to skip)", default: "")
        if spouse.lowercased() == "yes" || spouse.lowercased() == "y" {
            config.spouse = true
        } else if spouse.lowercased() == "no" || spouse.lowercased() == "n" {
            config.spouse = false
        }

        let deps = prompt("  Number of dependents (Enter to skip)", default: "")
        if let n = Int(deps) { config.dependents = n }

        let depsExcl = prompt("  Dependents excluding spouse (Enter to skip)", default: "")
        if let n = Int(depsExcl) { config.dependentsExclSpouse = n }

        // Education
        printHeader("Education History")
        if !western.education.isEmpty {
            print("  From your resume:")
            for edu in western.education {
                let dates = edu.graduationDate.map { " (\($0))" } ?? ""
                print("    - \(edu.institution) — \(edu.degree ?? "N/A")\(dates)")
            }
        }
        print("  Please provide details for each education entry.")
        print("  Include any education not on your resume (e.g. earlier schools).")
        print("  Entries will appear in chronological order on the 履歴書.\n")

        promptEducationEntries(western: western, config: &config)

        if confirm("\n  Add more education entries not on your resume?", default: false) {
            repeat {
                promptOneEducation(config: &config)
            } while confirm("  Add another?", default: false)
        }

        config.educationJapanese.sort { $0.yearMonth < $1.yearMonth }

        // Work history dates
        printHeader("Work History Dates")
        if !western.experience.isEmpty {
            print("  Confirm or correct dates for each position.")
            for exp in western.experience {
                guard exp.startDate != nil || exp.title != nil else { continue }
                let dates = "\(exp.startDate ?? "?") – \(exp.endDate ?? "?")"
                print("\n  \(exp.company) (\(exp.title ?? "N/A")) — \(dates)")
                if !confirm("    Dates correct?", default: true) {
                    let start = prompt("    Start date (e.g. 2020年1月)")
                    let end = prompt("    End date (e.g. 2023年5月, or 現在)")
                    config.workJapanese.append(
                        JapaneseEducationEntry(yearMonth: start, description: "\(exp.company) 入社")
                    )
                    if !["現在", "present", "current"].contains(end.lowercased()) {
                        config.workJapanese.append(
                            JapaneseEducationEntry(yearMonth: end, description: "一身上の都合により退職")
                        )
                    }
                }
            }
        }

        // Licenses
        printHeader("Licenses & Certifications")
        if !western.certifications.isEmpty {
            print("  From your resume:")
            for cert in western.certifications {
                print("    - \(cert)")
            }
        }
        print("  Add Japanese licenses/certifications (blank line to finish):")
        while true {
            let name = prompt("    License name (Enter to finish)", default: "")
            if name.isEmpty { break }
            let ym = prompt("    Year/Month (e.g. 2022年3月)")
            config.licenses.append(LicenseEntry(yearMonth: ym, name: name))
        }

        // Motivation & PR
        printHeader("Motivation & PR")
        let motivation = prompt("  志望動機 (motivation, Enter to auto-generate)", default: "")
        config.motivation = motivation.isEmpty ? nil : motivation

        let selfPr = prompt("  自己PR (self-promotion, Enter to auto-generate)", default: "")
        config.selfPr = selfPr.isEmpty ? nil : selfPr

        let hobbies = prompt("  趣味・特技 (hobbies/skills, Enter to skip)", default: "")
        config.hobbies = hobbies.isEmpty ? nil : hobbies

        return config
    }

    // MARK: - Education Helpers

    private static let completionTypes: [(key: String, jp: String, label: String)] = [
        ("1", "卒業", "Graduated"),
        ("2", "中途退学", "Withdrew (中途退学)"),
        ("3", "中途退学（一身上の都合により）", "Withdrew - personal reasons"),
        ("4", "中途退学（経済的理由により）", "Withdrew - financial reasons"),
        ("5", "中途退学（家庭の事情により）", "Withdrew - family circumstances"),
    ]

    private static func promptEducationEntries(western: WesternResume, config: inout JapanConfig) {
        for edu in western.education {
            print("  \(edu.institution) — \(edu.degree ?? "N/A")")
            let start = prompt("    Start date (e.g. 2010年1月 or 2010年8月)")
            let end = prompt("    End date (e.g. 2012年12月)")
            let degreeJp = prompt("    Degree in Japanese (e.g. コンピュータサイエンス学部)", default: "")
            let instJp = prompt("    Institution in Japanese (Enter to let AI translate)", default: "")

            let completionJp = promptCompletion()

            let instName = instJp.isEmpty ? edu.institution : instJp
            let degreeName = degreeJp.isEmpty ? (edu.degree ?? "") : degreeJp
            let label = "\(instName) \(degreeName)".trimmingCharacters(in: .whitespaces)

            config.educationJapanese.append(
                JapaneseEducationEntry(yearMonth: start, description: "\(label) 入学")
            )
            config.educationJapanese.append(
                JapaneseEducationEntry(yearMonth: end, description: "\(label) \(completionJp)")
            )
        }
    }

    private static func promptOneEducation(config: inout JapanConfig) {
        let institution = prompt("    Institution name")
        let instJp = prompt("    Institution in Japanese (Enter to let AI translate)", default: "")
        let degree = prompt("    Degree/Department (e.g. Computer Science)", default: "")
        let degreeJp = prompt("    Degree in Japanese (e.g. コンピュータサイエンス学部)", default: "")
        let start = prompt("    Start date (e.g. 2006年8月)")
        let end = prompt("    End date (e.g. 2008年5月)")

        let completionJp = promptCompletion()

        let instName = instJp.isEmpty ? institution : instJp
        let degreeName = degreeJp.isEmpty ? degree : degreeJp
        let label = "\(instName) \(degreeName)".trimmingCharacters(in: .whitespaces)

        config.educationJapanese.append(
            JapaneseEducationEntry(yearMonth: start, description: "\(label) 入学")
        )
        config.educationJapanese.append(
            JapaneseEducationEntry(yearMonth: end, description: "\(label) \(completionJp)")
        )
    }

    private static func promptCompletion() -> String {
        print("    Completion status:")
        for ct in completionTypes {
            print("      \(ct.key). \(ct.label)")
        }
        let choice = prompt("    Choose", default: "1")
        return completionTypes.first(where: { $0.key == choice })?.jp ?? "卒業"
    }

    // MARK: - Primitives

    static func prompt(_ message: String, default defaultValue: String? = nil) -> String {
        if let defaultValue, !defaultValue.isEmpty {
            print("\(message) (\(defaultValue)): ", terminator: "")
        } else {
            print("\(message): ", terminator: "")
        }
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines),
              !input.isEmpty else {
            return defaultValue ?? ""
        }
        return input
    }

    static func confirm(_ message: String, default defaultValue: Bool = false) -> Bool {
        let suffix = defaultValue ? "[Y/n]" : "[y/N]"
        print("\(message) \(suffix): ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !input.isEmpty else {
            return defaultValue
        }
        return input == "y" || input == "yes"
    }

    private static func printHeader(_ title: String) {
        print("\n\u{1B}[1m── \(title) ──\u{1B}[0m")
    }
}
