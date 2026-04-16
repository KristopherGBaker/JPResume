# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JPResume is a Swift CLI tool that converts western-style markdown resumes to Japanese format (履歴書 rirekisho and 職務経歴書 shokumukeirekisho). It uses CoreGraphics for native PDF rendering with Japanese fonts (Hiragino Sans).

## Build & Test Commands

```bash
make build                     # swift build
make test                      # swift test (43 tests, 6 suites)
make lint                      # swiftlint lint
make fix                       # swiftlint lint --fix
make project                   # xcodegen generate
make install                   # build release + copy to /usr/local/bin
make bootstrap                 # mint bootstrap (install tools from Mintfile)
swift run jpresume --help      # run CLI
swift run jpresume convert examples/resume.md --dry-run  # parse + normalize only, prints both
swift run jpresume convert examples/Kristopher_Baker_Resume.md --provider claude-cli --format both
```

## Architecture

Pipeline: **Parse → Normalize → Validate → Adapt → Render**

1. **Parser** (`Sources/JPResume/Parser/`) reads markdown into `WesternResume` (structured experience, education, skills, etc.). Uses `NSRegularExpression` for pattern matching. Supports H2, H3, and bold-text section headings.
2. **Config** (`Sources/JPResume/Config/`) loads `jpresume_config.yaml` (Japan-specific fields: kanji name, furigana, education dates, work history) or prompts interactively, then saves for reuse via Yams.
3. **Normalize** (`Sources/JPResume/AI/ResumeNormalizer.swift`) sends `WesternResume` + `JapanConfig` to LLM, returns `NormalizedResume` with structured dates, classified bullets (achievement vs responsibility), and categorized skills. Falls back to deterministic parsing if LLM fails. Cached to `.normalized_cache.json`.
4. **Validate** (`Sources/JPResume/Validation/ResumeValidator.swift`) runs rule-based checks on `NormalizedResume`: date range validity, isCurrent consistency, overlapping roles, total years of experience, low confidence entries. Emits warnings; use `--strict` to treat them as errors.
5. **Adapt** (`Sources/JPResume/AI/ResumeAI.swift`) sends `NormalizedResume` + `JapanConfig` to LLM, returns `RirekishoData` / `ShokumukeirekishoData` as JSON. Cached to `.rirekisho_cache.json` / `.shokumukeirekisho_cache.json`.
6. **Render** (`Sources/JPResume/Render/` + `Sources/JPResume/PDF/`) produces markdown (string interpolation templates) and PDF output (CoreGraphics).

### Intermediate Models

- `WesternResume` — raw parsed output from the deterministic parser. Dates are strings, bullets are flat.
- `NormalizedResume` — canonical intermediate produced by `ResumeNormalizer`. Contains `StructuredDate` (year/month ints), `NormalizedBullet` (with `.responsibility`/`.achievement` classification), `SkillCategory` groups, and per-entry `confidence` scores.

### AI Provider Abstraction

`AIProvider` protocol with `chat(system:user:temperature:) async throws -> String`. Six implementations using URLSession (API providers) or Process (CLI providers). Default provider is `ollama`. System prompts explicitly instruct the AI to never fabricate dates or details.

Normalization runs at temperature 0.2 (structured extraction). Adaptation runs at the default temperature 0.3.

### Caching

All three cache files (`.normalized_cache.json`, `.rirekisho_cache.json`, `.shokumukeirekisho_cache.json`) use content-based invalidation via `CacheEnvelope<T>`. The envelope stores a SHA-256 hash of markdown content + config JSON + schema version. Stale caches are automatically invalidated when any input changes.

### PDF Rendering

The rirekisho PDF is a grid-form layout drawn with absolute coordinates via `CGContext`, not HTML-to-PDF. Uses `NSFont(name: "HiraginoSans-W3")` for native Japanese font rendering. Supports multi-page overflow when work history is long.

### Tooling

- **SwiftLint** configured in `.swiftlint.yml`. Must pass with 0 violations before committing (`make lint`).
- **Mint** pins tool versions in `Mintfile` (SwiftLint, XcodeGen). `make bootstrap` installs them.
- **XcodeGen** generates `JPResume.xcodeproj` from `project.yml` (`make project`).

### Key Design Decisions

- CodingKeys use `snake_case` for YAML/JSON compatibility with external tools
- Education entries support 卒業 (graduation) and 中途退学 (withdrawal) with configurable reasons
- `work_japanese` config field stores additional work history not on the western resume (full timeline Japanese employers expect)
- Normalization uses JapanConfig as a source of ground-truth dates when available, so user-curated entries win over LLM inference
- AI responses are extracted via `JSONExtractor` (shared utility): code fences → direct parse → brace-match fallback
