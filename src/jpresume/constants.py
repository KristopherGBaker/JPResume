"""Constants for Japanese resume generation."""

# Japanese era periods (start_year, era_name)
ERAS = [
    (2019, "令和"),
    (1989, "平成"),
    (1926, "昭和"),
    (1912, "大正"),
    (1868, "明治"),
]

# All 47 prefectures
PREFECTURES = [
    "北海道",
    "青森県", "岩手県", "宮城県", "秋田県", "山形県", "福島県",
    "茨城県", "栃木県", "群馬県", "埼玉県", "千葉県", "東京都", "神奈川県",
    "新潟県", "富山県", "石川県", "福井県", "山梨県", "長野県", "岐阜県",
    "静岡県", "愛知県", "三重県",
    "滋賀県", "京都府", "大阪府", "兵庫県", "奈良県", "和歌山県",
    "鳥取県", "島根県", "岡山県", "広島県", "山口県",
    "徳島県", "香川県", "愛媛県", "高知県",
    "福岡県", "佐賀県", "長崎県", "熊本県", "大分県", "宮崎県", "鹿児島県",
    "沖縄県",
]

# Common section heading patterns for resume parsing
SECTION_PATTERNS: dict[str, list[str]] = {
    "summary": [
        "summary", "profile", "objective", "about", "overview",
        "professional summary", "career objective",
    ],
    "experience": [
        "experience", "work experience", "professional experience",
        "employment", "work history", "career history",
    ],
    "education": [
        "education", "academic", "qualifications",
    ],
    "skills": [
        "skills", "technical skills", "technologies", "competencies",
        "core competencies", "technical competencies",
        "languages & platforms",
    ],
    "certifications": [
        "certifications", "certificates", "licenses",
        "certifications and licenses", "professional certifications",
    ],
    "languages": [
        "languages", "language skills",
    ],
    "projects": [
        "projects", "personal projects", "side projects",
    ],
    "awards": [
        "awards", "honors", "achievements",
    ],
    "publications": [
        "publications", "papers",
    ],
    "volunteer": [
        "volunteer", "volunteering", "community",
    ],
}


def western_to_japanese_era(year: int, month: int = 1) -> str:
    """Convert a western year to Japanese era format.

    Example: 2020, 4 -> "令和2年4月"
    """
    for era_start, era_name in ERAS:
        if year >= era_start:
            era_year = year - era_start + 1
            if era_year == 1:
                return f"{era_name}元年{month}月"
            return f"{era_name}{era_year}年{month}月"
    return f"{year}年{month}月"


def western_year_month(year: int, month: int = 1) -> str:
    """Format as western-style Japanese date.

    Example: 2020, 4 -> "2020年4月"
    """
    return f"{year}年{month}月"
