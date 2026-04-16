import Foundation

enum MarkdownRenderer {
    static func renderRirekisho(_ data: RirekishoData) -> String {
        var lines: [String] = []
        lines.append("# 履歴書\n")
        lines.append("**作成日**: \(data.creationDate)\n")
        lines.append("---\n")

        // Basic info
        lines.append("## 基本情報\n")
        lines.append("| 項目 | 内容 |")
        lines.append("|------|------|")
        lines.append("| ふりがな | \(data.nameFurigana) |")
        lines.append("| 氏名 | \(data.nameKanji) |")
        lines.append("| 生年月日 | \(data.dateOfBirth) |")
        if let gender = data.gender { lines.append("| 性別 | \(gender) |") }
        lines.append("")

        // Contact
        lines.append("## 連絡先\n")
        lines.append("| 項目 | 内容 |")
        lines.append("|------|------|")
        if let pc = data.postalCode { lines.append("| 〒 | \(pc) |") }
        if let addr = data.address { lines.append("| 住所 | \(addr) |") }
        if let f = data.addressFurigana { lines.append("| ふりがな | \(f) |") }
        if let ph = data.phone { lines.append("| 電話番号 | \(ph) |") }
        if let em = data.email { lines.append("| メール | \(em) |") }
        lines.append("")

        // Education/Work
        lines.append("---\n")
        lines.append("## 学歴・職歴\n")
        lines.append("### 学歴\n")
        lines.append("| 年月 | 事項 |")
        lines.append("|------|------|")
        for entry in data.educationHistory {
            lines.append("| \(entry.date) | \(entry.description) |")
        }
        lines.append("")
        lines.append("### 職歴\n")
        lines.append("| 年月 | 事項 |")
        lines.append("|------|------|")
        for entry in data.workHistory {
            lines.append("| \(entry.date) | \(entry.description) |")
        }
        lines.append("|  | 以上 |")
        lines.append("")

        // Licenses
        if !data.licenses.isEmpty {
            lines.append("---\n")
            lines.append("## 免許・資格\n")
            lines.append("| 年月 | 免許・資格 |")
            lines.append("|------|-----------|")
            for entry in data.licenses {
                lines.append("| \(entry.date) | \(entry.description) |")
            }
            lines.append("")
        }

        // Motivation
        if let motivation = data.motivation {
            lines.append("---\n")
            lines.append("## 志望動機\n")
            lines.append(motivation)
            lines.append("")
        }

        // Hobbies
        if let hobbies = data.hobbies {
            lines.append("---\n")
            lines.append("## 趣味・特技\n")
            lines.append(hobbies)
            lines.append("")
        }

        // Other info
        lines.append("---\n")
        lines.append("## その他\n")
        lines.append("| 項目 | 内容 |")
        lines.append("|------|------|")
        if let ct = data.commuteTime { lines.append("| 通勤時間 | \(ct) |") }
        if let s = data.spouse { lines.append("| 配偶者 | \(s ? "有" : "無") |") }
        if let d = data.dependents { lines.append("| 扶養家族数 | \(d)人 |") }
        if let de = data.dependentsExclSpouse { lines.append("| 扶養家族数（配偶者を除く） | \(de)人 |") }
        lines.append("")

        return lines.joined(separator: "\n")
    }

    static func renderShokumukeirekisho(_ data: ShokumukeirekishoData) -> String {
        var lines: [String] = []
        lines.append("# 職務経歴書\n")
        lines.append("**作成日**: \(data.creationDate)")
        lines.append("**氏名**: \(data.name)\n")
        lines.append("---\n")

        // Career summary
        lines.append("## 職務要約\n")
        lines.append(data.careerSummary)
        lines.append("\n---\n")

        // Work details
        lines.append("## 職務経歴\n")
        for company in data.workDetails {
            lines.append("### \(company.companyName)（\(company.period)）\n")
            lines.append("| 項目 | 内容 |")
            lines.append("|------|------|")
            if let ind = company.industry { lines.append("| 事業内容 | \(ind) |") }
            if let sz = company.companySize { lines.append("| 従業員数 | \(sz) |") }
            if let et = company.employmentType { lines.append("| 雇用形態 | \(et) |") }
            lines.append("")
            if let role = company.role {
                var roleStr = "**\(role)**"
                if let dept = company.department { roleStr += "（\(dept)）" }
                lines.append(roleStr)
                lines.append("")
            }
            if !company.responsibilities.isEmpty {
                lines.append("**業務内容:**\n")
                for item in company.responsibilities { lines.append("- \(item)") }
                lines.append("")
            }
            if !company.achievements.isEmpty {
                lines.append("**主な実績:**\n")
                for item in company.achievements { lines.append("- \(item)") }
                lines.append("")
            }
            lines.append("---\n")
        }

        // Technical skills
        lines.append("## 活かせる経験・知識・技術\n")
        for (category, skills) in data.technicalSkills {
            lines.append("| \(category) | \(skills.joined(separator: ", ")) |")
        }
        lines.append("")

        // Self PR
        if let pr = data.selfPr {
            lines.append("---\n")
            lines.append("## 自己PR\n")
            lines.append(pr)
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }
}
