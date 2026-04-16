import Foundation

struct JapaneseAddress: Codable, Sendable {
    var postalCode: String?
    var prefecture: String?
    var city: String?
    var line1: String?
    var line2: String?
    var furigana: String?

    enum CodingKeys: String, CodingKey {
        case prefecture, city, line1, line2, furigana
        case postalCode = "postal_code"
    }

    init(postalCode: String? = nil, prefecture: String? = nil, city: String? = nil,
         line1: String? = nil, line2: String? = nil, furigana: String? = nil) {
        self.postalCode = postalCode
        self.prefecture = prefecture
        self.city = city
        self.line1 = line1
        self.line2 = line2
        self.furigana = furigana
    }
}

struct JapaneseEducationEntry: Codable, Sendable {
    var yearMonth: String
    var description: String

    enum CodingKeys: String, CodingKey {
        case description
        case yearMonth = "year_month"
    }
}

struct LicenseEntry: Codable, Sendable {
    var yearMonth: String
    var name: String

    enum CodingKeys: String, CodingKey {
        case name
        case yearMonth = "year_month"
    }
}

struct JapanConfig: Codable, Sendable {
    var nameKanji: String?
    var nameFurigana: String?
    var dateOfBirth: String?
    var gender: String?
    var addressCurrent: JapaneseAddress
    var addressContact: JapaneseAddress?
    var phone: String?
    var email: String?
    var photoPath: String?
    var commuteTime: String?
    var spouse: Bool?
    var dependents: Int?
    var dependentsExclSpouse: Int?
    var motivation: String?
    var hobbies: String?
    var selfPr: String?
    var educationJapanese: [JapaneseEducationEntry]
    var workJapanese: [JapaneseEducationEntry]
    var licenses: [LicenseEntry]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nameKanji = try container.decodeIfPresent(String.self, forKey: .nameKanji)
        nameFurigana = try container.decodeIfPresent(String.self, forKey: .nameFurigana)
        dateOfBirth = try container.decodeIfPresent(String.self, forKey: .dateOfBirth)
        gender = try container.decodeIfPresent(String.self, forKey: .gender)
        addressCurrent = try container.decodeIfPresent(JapaneseAddress.self, forKey: .addressCurrent) ?? JapaneseAddress()
        addressContact = try container.decodeIfPresent(JapaneseAddress.self, forKey: .addressContact)
        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        photoPath = try container.decodeIfPresent(String.self, forKey: .photoPath)
        commuteTime = try container.decodeIfPresent(String.self, forKey: .commuteTime)
        spouse = try container.decodeIfPresent(Bool.self, forKey: .spouse)
        dependents = try container.decodeIfPresent(Int.self, forKey: .dependents)
        dependentsExclSpouse = try container.decodeIfPresent(Int.self, forKey: .dependentsExclSpouse)
        motivation = try container.decodeIfPresent(String.self, forKey: .motivation)
        hobbies = try container.decodeIfPresent(String.self, forKey: .hobbies)
        selfPr = try container.decodeIfPresent(String.self, forKey: .selfPr)
        educationJapanese = try container.decodeIfPresent([JapaneseEducationEntry].self, forKey: .educationJapanese) ?? []
        workJapanese = try container.decodeIfPresent([JapaneseEducationEntry].self, forKey: .workJapanese) ?? []
        licenses = try container.decodeIfPresent([LicenseEntry].self, forKey: .licenses) ?? []
    }

    enum CodingKeys: String, CodingKey {
        case gender, phone, email, spouse, dependents, motivation, hobbies, licenses
        case nameKanji = "name_kanji"
        case nameFurigana = "name_furigana"
        case dateOfBirth = "date_of_birth"
        case addressCurrent = "address_current"
        case addressContact = "address_contact"
        case photoPath = "photo_path"
        case commuteTime = "commute_time"
        case dependentsExclSpouse = "dependents_excl_spouse"
        case selfPr = "self_pr"
        case educationJapanese = "education_japanese"
        case workJapanese = "work_japanese"
    }

    init(nameKanji: String? = nil, nameFurigana: String? = nil,
         dateOfBirth: String? = nil, gender: String? = nil,
         addressCurrent: JapaneseAddress = JapaneseAddress(),
         addressContact: JapaneseAddress? = nil,
         phone: String? = nil, email: String? = nil,
         photoPath: String? = nil, commuteTime: String? = nil,
         spouse: Bool? = nil, dependents: Int? = nil,
         dependentsExclSpouse: Int? = nil,
         motivation: String? = nil, hobbies: String? = nil,
         selfPr: String? = nil,
         educationJapanese: [JapaneseEducationEntry] = [],
         workJapanese: [JapaneseEducationEntry] = [],
         licenses: [LicenseEntry] = []) {
        self.nameKanji = nameKanji
        self.nameFurigana = nameFurigana
        self.dateOfBirth = dateOfBirth
        self.gender = gender
        self.addressCurrent = addressCurrent
        self.addressContact = addressContact
        self.phone = phone
        self.email = email
        self.photoPath = photoPath
        self.commuteTime = commuteTime
        self.spouse = spouse
        self.dependents = dependents
        self.dependentsExclSpouse = dependentsExclSpouse
        self.motivation = motivation
        self.hobbies = hobbies
        self.selfPr = selfPr
        self.educationJapanese = educationJapanese
        self.workJapanese = workJapanese
        self.licenses = licenses
    }
}
