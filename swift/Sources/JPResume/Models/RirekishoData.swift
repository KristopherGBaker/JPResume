import Foundation

struct DateDescription: Codable, Sendable {
    var date: String
    var description: String

    init(_ date: String, _ description: String) {
        self.date = date
        self.description = description
    }

    init(from decoder: Decoder) throws {
        // Support both object format and array format [date, description]
        if let container = try? decoder.singleValueContainer(),
           let array = try? container.decode([String].self),
           array.count == 2 {
            self.date = array[0]
            self.description = array[1]
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.date = try container.decode(String.self, forKey: .date)
            self.description = try container.decode(String.self, forKey: .description)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(date)
        try container.encode(description)
    }

    private enum CodingKeys: String, CodingKey {
        case date, description
    }
}

struct RirekishoData: Codable, Sendable {
    var creationDate: String
    var nameKanji: String
    var nameFurigana: String
    var dateOfBirth: String
    var gender: String?
    var postalCode: String?
    var address: String?
    var addressFurigana: String?
    var contactPostalCode: String?
    var contactAddress: String?
    var contactAddressFurigana: String?
    var phone: String?
    var email: String?
    var photoPath: String?
    var educationHistory: [DateDescription]
    var workHistory: [DateDescription]
    var licenses: [DateDescription]
    var motivation: String?
    var hobbies: String?
    var commuteTime: String?
    var spouse: Bool?
    var dependents: Int?
    var dependentsExclSpouse: Int?

    enum CodingKeys: String, CodingKey {
        case gender, address, phone, email, motivation, hobbies, spouse, dependents, licenses
        case creationDate = "creation_date"
        case nameKanji = "name_kanji"
        case nameFurigana = "name_furigana"
        case dateOfBirth = "date_of_birth"
        case postalCode = "postal_code"
        case addressFurigana = "address_furigana"
        case contactPostalCode = "contact_postal_code"
        case contactAddress = "contact_address"
        case contactAddressFurigana = "contact_address_furigana"
        case photoPath = "photo_path"
        case educationHistory = "education_history"
        case workHistory = "work_history"
        case commuteTime = "commute_time"
        case dependentsExclSpouse = "dependents_excl_spouse"
    }
}
