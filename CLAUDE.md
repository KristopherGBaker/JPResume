# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JPResume is a Swift CLI tool that converts western-style markdown resumes to Japanese format (履歴書 rirekisho and 職務経歴書 shokumukeirekisho). It uses CoreGraphics for native PDF rendering with Japanese fonts (Hiragino Sans).

## Build & Test Commands

```bash
swift build                    # build
swift test                     # run all tests (15 tests, 3 suites)
swift run jpresume --help      # run CLI
swift run jpresume convert examples/resume.md --dry-run  # parse only
swift run jpresume convert examples/Kristopher_Baker_Resume.md --provider claude-cli --format both
xcodegen generate              # regenerate Xcode project from project.yml
```

## Architecture

Pipeline: **Parse → Config → AI → Render**

1. **Parser** (`Sources/JPResume/Parser/`) reads markdown into `WesternResume` (structured experience, education, skills, etc.). Uses `NSRegularExpression` for pattern matching. Supports H2, H3, and bold-text section headings.
2. **Config** (`Sources/JPResume/Config/`) loads `jpresume_config.yaml` (Japan-specific fields: kanji name, furigana, education dates, work history) or prompts interactively, then saves for reuse via Yams.
3. **AI** (`Sources/JPResume/AI/`) sends `WesternResume` + `JapanConfig` to an LLM provider, which returns `RirekishoData` / `ShokumukeirekishoData` as JSON. Results are cached to `.rirekisho_cache.json` / `.shokumukeirekisho_cache.json`.
4. **Render** (`Sources/JPResume/Render/` + `Sources/JPResume/PDF/`) produces markdown (string interpolation templates) and PDF output (CoreGraphics).

### AI Provider Abstraction

`AIProvider` protocol with `chat(system:user:temperature:) async throws -> String`. Six implementations using URLSession (API providers) or Process (CLI providers). Default provider is `ollama`. System prompts explicitly instruct the AI to never fabricate dates or details.

### PDF Rendering

The rirekisho PDF is a grid-form layout drawn with absolute coordinates via `CGContext`, not HTML-to-PDF. Uses `NSFont(name: "HiraginoSans-W3")` for native Japanese font rendering. Supports multi-page overflow when work history is long.

### Key Design Decisions

- CodingKeys use `snake_case` for YAML/JSON compatibility with external tools
- Education entries support 卒業 (graduation) and 中途退学 (withdrawal) with configurable reasons
- `work_japanese` config field stores additional work history not on the western resume (full timeline Japanese employers expect)
- AI responses are extracted from markdown code fences or brace-matched when the LLM adds trailing text
