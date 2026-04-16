# JPResume

Convert western-style resumes to Japanese format: 履歴書 (rirekisho) and 職務経歴書 (shokumukeirekisho).

Takes a markdown resume as input, gathers Japan-specific details interactively, uses AI to translate and adapt the content, and generates both markdown and PDF output.

## Features

- **Markdown resume parser** - handles H2, H3, and bold-text section headings
- **LLM normalization** - structures ambiguous dates, classifies bullets as achievements vs responsibilities, categorizes skills
- **Validation** - checks date ranges, overlapping roles, current role consistency, total years of experience
- **Interactive config** - prompts for Japan-specific fields (kanji name, furigana, address, education dates, etc.), saves to YAML for reuse
- **Education support** - handles 卒業 (graduation) and 中途退学 (withdrawal) with optional reasons
- **Multi-provider AI** - Anthropic, OpenAI, OpenRouter, Ollama, Claude CLI, Codex CLI
- **Content-based caching** - all AI output cached with SHA-256 content hashing; automatically invalidated when inputs change
- **PDF output** - rirekisho as a standard grid-form layout (CoreGraphics), shokumukeirekisho as a free-form document
- **Markdown output** - editable templates for both resume types

## Requirements

- macOS 15+
- Swift 6.2 (Xcode or Swift toolchain)
- [Mint](https://github.com/yonaskolb/Mint) (optional, for tool management)

## Build & Run

```bash
make build                     # swift build
make test                      # swift test
make lint                      # swiftlint lint
make fix                       # swiftlint lint --fix
make project                   # xcodegen generate
make install                   # release build + install to /usr/local/bin
make bootstrap                 # mint bootstrap (install SwiftLint + XcodeGen)
```

Or directly:

```bash
swift build
swift run jpresume convert examples/resume.md --provider claude-cli --format both
```

## Usage

```
jpresume convert <input.md> [options]

Options:
  -o, --output-dir DIR          Output directory (default: same as input)
  -c, --config PATH             Config file path (default: {input_dir}/jpresume_config.yaml)
  --reconfigure                 Re-prompt for all Japan-specific fields
  --format {markdown,pdf,both}  Output format (default: both)
  --rirekisho-only              Generate only the rirekisho (履歴書)
  --shokumukeirekisho-only      Generate only the shokumukeirekisho (職務経歴書)
  --provider PROVIDER           AI provider (default: ollama)
  --model MODEL                 Model name override
  --era {western,japanese}      Date format: 2024年3月 vs 令和6年3月 (default: western)
  --no-cache                    Ignore all cached output and regenerate
  --strict                      Treat validation warnings as errors
  --dry-run                     Parse + normalize only, print both and exit
  -v, --verbose                 Show AI prompts/responses
```

## AI Providers

| Provider | Flag | API Key Env | Notes |
|----------|------|-------------|-------|
| Ollama | `--provider ollama` | (none) | Local, default |
| Claude CLI | `--provider claude-cli` | (none) | Uses `claude -p` |
| Codex CLI | `--provider codex-cli` | (none) | Uses `codex exec` |
| OpenRouter | `--provider openrouter` | `OPENROUTER_API_KEY` | |
| OpenAI | `--provider openai` | `OPENAI_API_KEY` | |
| Anthropic | `--provider anthropic` | `ANTHROPIC_API_KEY` | |

## Workflow

1. **Parse** - markdown resume is parsed into structured data (`WesternResume`)
2. **Config** - Japan-specific fields loaded from YAML or prompted interactively (saved for reuse)
3. **Normalize** - LLM structures ambiguous dates into year/month, classifies bullets as achievements vs responsibilities, groups skills into categories. Falls back to deterministic parsing if LLM fails. Uses config dates as ground truth. Cached to `.normalized_cache.json`.
4. **Validate** - rule-based checks on the normalized resume: date ranges, overlaps, isCurrent consistency, total experience, low-confidence entries. Warnings printed to console; `--strict` treats them as errors.
5. **Adapt** - LLM translates and adapts to Japanese conventions, producing `RirekishoData` and `ShokumukeirekishoData`. Cached to `.rirekisho_cache.json` / `.shokumukeirekisho_cache.json`.
6. **Render** - output generated as markdown and/or PDF

All three caches use content-based invalidation (SHA-256 of markdown + config + schema version) — they update automatically when any input changes.

## Config

Japan-specific data is stored in `jpresume_config.yaml` alongside the input resume:

- Name in kanji and furigana
- Date of birth, gender
- Address with furigana
- Education history with start/end dates and completion status
- Additional work history not on the western resume
- Licenses and certifications
- Motivation (志望動機), hobbies (趣味・特技), self-PR (自己PR)
- Commute time, spouse, dependents

## Tooling

- **Mint** - `Mintfile` pins SwiftLint and XcodeGen versions. Run `make bootstrap` to install.
- **SwiftLint** - configured in `.swiftlint.yml`. Run `make lint` to check, `make fix` to auto-fix.
- **XcodeGen** - `project.yml` generates the Xcode project. Run `make project` to regenerate.
