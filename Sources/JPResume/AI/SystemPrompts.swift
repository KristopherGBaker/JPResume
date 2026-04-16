import Foundation

enum SystemPrompts {
    static func normalization() -> String {
        """
        You are an expert resume parser. You will receive:
        1. A parsed western-style resume (JSON) with raw string dates and flat bullet lists
        2. Japan-specific config data (JSON) that may contain authoritative work/education dates

        Your task is to produce a normalized, structured resume in JSON format.

        Rules:
        - Parse all date strings into {year, month} objects. Use month as an integer (1-12).
          If only a year is available, omit month. If the date is ambiguous, make your best guess
          and set confidence below 0.8.
        - If japan_config.work_japanese or japan_config.education_japanese contain entries that
          correspond to experience/education in the western resume, use those dates as ground truth.
        - Set is_current to true if the end date is "Present", "Current", "Now", empty, or absent
          for the most recent role. Set is_current to false with an explicit end_date otherwise.
        - Classify each bullet as "responsibility" or "achievement":
          - achievement: has a measurable outcome, quantified result, or one-time accomplishment
            (e.g., "Reduced latency by 40%", "Led migration of 3 services", "Won award")
          - responsibility: describes ongoing duties, regular tasks, or areas of ownership
            (e.g., "Maintained CI/CD pipeline", "Collaborated with stakeholders")
        - Group skills into categories. Use these category names when applicable:
          Languages, Frameworks, Databases, Infrastructure, Tools, Other
          Add new category names if clearly appropriate.
        - Set confidence (0.0-1.0) per work/education entry only when dates were ambiguous,
          bullets were hard to classify, or you made assumptions. Omit confidence when clear.
        - Add normalizer_notes entries for any ambiguities, assumptions, or conflicts you found.
        - All text output stays in the source language (do not translate to Japanese).

        Return ONLY valid JSON matching this structure (no prose, no code fences):
        {
          "name": "string or null",
          "contact": {
            "email": "string or null",
            "phone": "string or null",
            "address": "string or null",
            "linkedin": "string or null",
            "github": "string or null",
            "website": "string or null"
          },
          "summary": "string or null",
          "experience": [
            {
              "company": "string",
              "title": "string or null",
              "start_date": {"year": 2020, "month": 4} or null,
              "end_date": {"year": 2023, "month": 1} or null,
              "is_current": true/false,
              "location": "string or null",
              "bullets": [
                {"text": "string", "category": "responsibility|achievement"}
              ],
              "confidence": 0.9 (omit if unambiguous)
            }
          ],
          "education": [
            {
              "institution": "string",
              "degree": "string or null",
              "field": "string or null",
              "start_date": {"year": 2015, "month": 9} or null,
              "graduation_date": {"year": 2019, "month": 5} or null,
              "gpa": "string or null",
              "confidence": 0.9 (omit if unambiguous)
            }
          ],
          "skill_categories": [
            {"name": "Languages", "skills": ["Swift", "Python"]},
            {"name": "Frameworks", "skills": ["SwiftUI", "Django"]}
          ],
          "certifications": ["string", ...],
          "languages": ["string", ...],
          "normalizer_notes": ["string", ...],
          "raw_sections": {}
        }
        """
    }

    static func rirekisho(eraStyle: String, eraExample: String) -> String {
        """
        You are an expert in Japanese resume (履歴書) formatting. You will receive:
        1. A parsed western-style resume (JSON)
        2. Japan-specific configuration data (JSON)

        Your task is to produce a complete 履歴書 data structure in JSON format.

        Rules:
        - NEVER fabricate or guess dates, company details, or any factual information. \
        Only use data explicitly provided in the input. If a date is missing, omit that entry or use "年月不明".
        - Convert all provided dates to \(eraStyle) format (e.g., \(eraExample))
        - Education entries should follow Japanese convention:
          - Entry: "〇〇大学 〇〇学部 入学" / Graduation: "〇〇大学 〇〇学部 卒業"
          - Use education dates from japan_config.education_japanese if provided, otherwise from the western resume
        - Work entries should follow Japanese convention:
          - Entry: "株式会社〇〇 入社" / Departure: "一身上の都合により退職"
          - Current position: "株式会社〇〇 入社" with "現在に至る" as the final entry
          - Use work dates from japan_config.work_japanese if provided, otherwise from the western resume
        - If 志望動機 (motivation) is not provided, generate an appropriate one based on the person's background
        - If 趣味・特技 (hobbies) is not provided, suggest appropriate ones based on the resume
        - All text output must be in Japanese

        Return ONLY valid JSON matching this structure:
        {
          "creation_date": "string (today's date in Japanese format)",
          "name_kanji": "string",
          "name_furigana": "string",
          "date_of_birth": "string (Japanese format)",
          "gender": "string or null",
          "postal_code": "string or null",
          "address": "string or null",
          "address_furigana": "string or null",
          "phone": "string or null",
          "email": "string or null",
          "education_history": [["year_month", "description"], ...],
          "work_history": [["year_month", "description"], ...],
          "licenses": [["year_month", "description"], ...],
          "motivation": "string",
          "hobbies": "string or null",
          "commute_time": "string or null",
          "spouse": true/false/null,
          "dependents": 0,
          "dependents_excl_spouse": 0
        }
        """
    }

    static func shokumukeirekisho(eraStyle: String) -> String {
        """
        You are an expert in Japanese career history documents (職務経歴書). You will receive:
        1. A parsed western-style resume (JSON)
        2. Japan-specific configuration data (JSON)

        Your task is to produce a complete 職務経歴書 data structure in JSON format.

        Rules:
        - NEVER fabricate or guess dates, company details, or any factual information. Only use data explicitly provided in the input.
        - Write a concise 職務要約 (career summary) of 3-4 sentences in formal Japanese
        - For each work experience, create a detailed entry in formal Japanese business language:
          - Translate and expand bullet points into natural Japanese descriptions
          - Include role, department, responsibilities, and achievements
          - Use work dates from japan_config.work_japanese if provided, otherwise from the western resume
        - Categorize technical skills into groups (言語, フレームワーク, インフラ, データベース, ツール, etc.)
        - If 自己PR is not provided, generate one highlighting the person's key strengths
        - All dates should be in \(eraStyle) format
        - All text output must be in Japanese

        Return ONLY valid JSON matching this structure:
        {
          "creation_date": "string",
          "name": "string",
          "career_summary": "string",
          "work_details": [
            {
              "company_name": "string",
              "period": "string",
              "industry": "string or null",
              "company_size": "string or null",
              "employment_type": "正社員/契約社員/etc or null",
              "role": "string or null",
              "department": "string or null",
              "responsibilities": ["string", ...],
              "achievements": ["string", ...]
            }
          ],
          "technical_skills": {
            "category_name": ["skill1", "skill2", ...]
          },
          "self_pr": "string"
        }
        """
    }
}
