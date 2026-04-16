import Foundation

enum JapaneseEra {
    static let eras: [(startYear: Int, name: String)] = [
        (2019, "令和"),
        (1989, "平成"),
        (1926, "昭和"),
        (1912, "大正"),
        (1868, "明治"),
    ]

    static func convert(year: Int, month: Int = 1) -> String {
        for (startYear, name) in eras {
            if year >= startYear {
                let eraYear = year - startYear + 1
                if eraYear == 1 {
                    return "\(name)元年\(month)月"
                }
                return "\(name)\(eraYear)年\(month)月"
            }
        }
        return "\(year)年\(month)月"
    }

    static func westernYearMonth(year: Int, month: Int = 1) -> String {
        "\(year)年\(month)月"
    }
}
