# `jpresume_config.yaml` reference

Japan-specific fields the CLI needs beyond what a western resume source provides. Stored as YAML, loaded by `Sources/JPResume/Config/`, and snapshotted into `inputs.json` during `parse`.

Reference example: [`jpresume_config.example.yaml`](jpresume_config.example.yaml) (fictional, paired to the repo's `examples/resume.md`).

## Draftable template

Use this when the user doesn't already have a config. Fill in fields with the user before running `parse`.

```yaml
# Name in kanji (or katakana for non-Japanese names). Full-width space between surname and given name.
name_kanji: スミス　ジョン
# Furigana — phonetic reading. Hiragana for Japanese names, katakana for non-Japanese names.
name_furigana: スミス　ジョン

# ISO date.
date_of_birth: '1991-06-15'
gender: Male                  # Male | Female | (Japanese resumes historically require this field)

# Current address. Break into parts for the rirekisho grid form.
address_current:
  postal_code: 100-0001
  prefecture: 東京都
  city: 千代田区
  line1: 千代田1-1-1
  furigana: ちよだ1-1-1        # furigana for the address (hiragana for kanji portions)

phone: 090-1234-5678
email: john.smith@example.com

# Household fields (optional but expected on traditional 履歴書).
spouse: false                 # 配偶者
dependents: 0                 # 扶養家族数（配偶者除く）
dependents_excl_spouse: 0

# Education timeline — one entry per 入学/卒業/中途退学 event.
# Produces the 学歴 section of the rirekisho in Japanese conventions.
education_japanese:
  - year_month: 2009年8月
    description: University of California, Berkeley コンピュータサイエンス学部 入学
  - year_month: 2013年5月
    description: University of California, Berkeley コンピュータサイエンス学部 卒業

# Full Japanese-style work history.
# Use this for roles that aren't on the western resume but belong on a 職歴 timeline,
# OR to provide authoritative dates when the source resume's dates are ambiguous.
# Each job gets an 入社 and a 退職 entry (or 一身上の都合により退職 for personal reasons).
work_japanese:
  - year_month: 2013年6月
    description: WebDev Agency 入社
  - year_month: 2016年2月
    description: 一身上の都合により退職
  - year_month: 2016年3月
    description: TechStart Inc 入社
  # … continue chronologically …

# Licenses / certifications with Japanese date format.
licenses:
  - year_month: 2022年7月
    name: JLPT N2
  - year_month: 2022年3月
    name: AWS Solutions Architect Associate

# Optional free-text fields. If omitted, the LLM will draft them from the source resume.
# motivation:  志望動機 (why this company/role)
# hobbies:     趣味・特技
# self_pr:     自己PR (longer-form pitch)
# commute_time_minutes: 45
```

## Field notes

### `name_kanji`

- Use full-width space (`　`) between surname and given name — this is the Japanese convention for the rirekisho grid.
- Non-Japanese names typically use katakana (ベイカー　クリストファー) rather than kanji.

### `name_furigana`

- Hiragana for Japanese names, katakana for non-Japanese names. Matches whatever form the hiring manager expects to read first.
- Same full-width space separator.

### `address_current.furigana`

- Furigana reading for the kanji portion of the address. The line1 section (street + building + unit) is read in hiragana.
- Numbers and Latin characters stay as-is.

### `education_japanese`

- One entry per event: 入学 (enrolled), 卒業 (graduated), 中途退学 (withdrew).
- `year_month` uses western era by default (`2012年12月`). Use reiwa (`令和X年M月`) only if the whole document will use `--era japanese`.
- The parser pairs 入学/卒業 into institution blocks automatically in the rirekisho.

### `work_japanese`

- **Source of truth for dates** when the western resume has ambiguous phrasing like "2019 - present". The LLM is instructed to prefer config dates over source-resume dates during `normalize`.
- Include *every* employer that will appear on the rirekisho's 職歴 timeline. Japanese resumes show all past employers, even brief stints — don't trim.
- Use `一身上の都合により退職` for "left for personal reasons" (standard euphemism). Use `会社都合により退職` for layoffs / company-initiated.
- Freelance: `フリーランス <domain>` for entry, `フリーランス業務終了` for exit.

### `licenses`

- Japanese convention lists certifications chronologically by acquisition date with Japanese date format.
- JLPT results, driver's licenses, professional certifications all go here.

## When to edit config vs. edit `normalized.json`

| Concern | Edit which |
|---------|------------|
| Missing employer, wrong employment date, missing education event | `jpresume_config.yaml` — then re-run `parse` + `normalize` |
| Bullet classification (achievement vs responsibility), skill grouping | `normalized.json` directly, then `repair` |
| Japanese phrasing of a specific sentence in the output | `rirekisho.json` / `shokumukeirekisho.json` directly, then `render` |
| Global era change (western ↔ reiwa) | Re-run `generate` stages with `--era` flag; no config change needed |

Editing the config triggers a full hash invalidation (via `inputs.json`), so every downstream stage reruns. Editing `normalized.json` only invalidates from `repair` onward. Editing the final JSON only invalidates `render`.
