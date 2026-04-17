# JPResume

Convert western-style resumes to Japanese format: 履歴書 (rirekisho) and 職務経歴書 (shokumukeirekisho).

Takes a markdown resume as input, gathers Japan-specific details, uses AI to translate and adapt the content, and generates both markdown and PDF output.

## Recommended usage — agent skill

The best way to use JPResume is through its **agent skill** with Claude Code, Cursor, Codex, or another supported AI coding assistant. The agent drives the pipeline stage-by-stage in `--external` mode: it acts as the LLM for the normalize and generate stages, pauses after validation so you can review and correct the normalized resume, and produces output you can inspect and refine interactively — all without leaving your editor.

Install the skill:

```bash
npx skills add KristopherGBaker/JPResume
```

Then ask your agent: *"Help me create a Japanese resume from my resume.md"* or *"Generate a rirekisho for [company name]"*.

The agent will:
1. Run `jpresume parse` → `normalize` → `repair` → `validate` (and pause for your review)
2. Produce the 履歴書 and 職務経歴書 JSON itself, in external mode
3. Ask about era style, side projects, older roles, and — if applying to a specific company — use `--target` to tailor 志望動機, 職務要約, and 自己PR
4. Render final PDF and markdown output

See [skills/japanese-resume/SKILL.md](skills/japanese-resume/SKILL.md) for the full protocol and the [references/](skills/japanese-resume/references/) folder for config schema and examples.

---

The CLI can also be used standalone for one-shot or batch generation — see [Usage](#usage) below.

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
- Swift 6.2 only required if building from source or using Mint

## Install

### Pre-built universal binary (recommended)

Download the latest release binary directly — no Swift toolchain required:

```bash
curl -L https://github.com/KristopherGBaker/JPResume/releases/latest/download/jpresume \
  -o /usr/local/bin/jpresume && chmod +x /usr/local/bin/jpresume
```

Or download manually from the [Releases page](https://github.com/KristopherGBaker/JPResume/releases).

### mise

If you use [mise](https://mise.jdx.dev), install via the `ubi` backend:

```bash
mise use -g ubi:KristopherGBaker/JPResume
```

Or pin a version in `mise.toml`:

```toml
[tools]
"ubi:KristopherGBaker/JPResume" = "0.3.0"
```

### Mint

Install via [Mint](https://github.com/yonaskolb/Mint) (builds from source — requires Swift 6.2):

```bash
mint install KristopherGBaker/JPResume
```

### Build from source

```bash
git clone https://github.com/KristopherGBaker/JPResume.git
cd JPResume
make install   # release build → /usr/local/bin/jpresume
```

## Build & Run (contributors)

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
  --workspace DIR               Intermediate-artifact workspace (default: <outputDir>/.jpresume)
  --reconfigure                 Re-prompt for all Japan-specific fields
  --format {markdown,pdf,both}  Output format (default: both)
  --rirekisho-only              Generate only the rirekisho (履歴書)
  --shokumukeirekisho-only      Generate only the shokumukeirekisho (職務経歴書)
  --provider PROVIDER           AI provider (default: ollama)
  --model MODEL                 Model name override
  --era {western,japanese}      Date format: 2024年3月 vs 令和6年3月 (default: western)
  --target PATH                 Path to target-company context JSON (tailored application mode)
  --no-cache                    Ignore all cached output and regenerate
  --strict                      Treat validation warnings as errors
  --dry-run                     Parse + normalize only, print both and exit
  -v, --verbose                 Show AI prompts/responses
```

**Target-company context** (`--target company.json`) switches from neutral master-document mode to tailored application mode. The JSON file can contain any combination of: `company_name`, `role_title`, `company_summary`, `job_description_excerpt`, `normalized_requirements`, `emphasis_tags` (e.g. `"mobile"`, `"consumer"`, `"growth"`, `"ai"`), `candidate_interest_notes`. When present, 志望動機, 職務要約, 自己PR, and role emphasis are adjusted toward the target — using only facts from the input, never fabricating.

For per-stage commands (`parse`, `normalize`, `validate`, `repair`, `generate`, `render`, `inspect`), see the [Stepwise / agent workflow](#stepwise--agent-workflow) section.

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
3. **Normalize** - LLM structures ambiguous dates into year/month, classifies bullets as achievements vs responsibilities, groups skills into categories. Falls back to deterministic parsing if LLM fails. Uses config dates as ground truth.
4. **Validate** - rule-based checks on the normalized resume: date ranges, overlaps, isCurrent consistency, total experience, low-confidence entries. Warnings printed to console; `--strict` treats them as errors.
5. **Repair** - consistency checker applies safe repairs (sort chronologically, fix overlapping dates, resolve `is_current` inconsistencies) and computes derived experience metrics.
6. **Adapt** - LLM translates and adapts to Japanese conventions, producing `RirekishoData` and `ShokumukeirekishoData`.
7. **Polish + Render** - deterministic text polish runs over generated data; output emitted as markdown and/or PDF.

Each stage writes a versioned JSON artifact into `<outputDir>/.jpresume/` so reruns skip unchanged work (SHA-256 content-based invalidation covers markdown + config + era + generation options + schema version).

## Stepwise / agent workflow

In addition to `convert`, jpresume exposes one subcommand per pipeline stage. This is designed for human review between stages and for use as a skill by LLM agents.

```
jpresume parse <input.md> [--workspace .jpresume]
jpresume normalize [--workspace] [--provider] [--external | --ingest]
jpresume validate [--workspace] [--on normalized|repaired]
jpresume repair [--workspace]
jpresume generate rirekisho [--workspace] [--provider] [--era] [--target company.json] [--external | --ingest]
jpresume generate shokumukeirekisho [--workspace] [--include-side-projects] [--era] [--target company.json] [--external | --ingest]
jpresume render [rirekisho|shokumukeirekisho|both] [--workspace] [--output-dir]
jpresume inspect [<artifact>] [--workspace] [--json]
```

### Workspace layout

Every run — stepwise or `convert` — populates a workspace directory:

```
.jpresume/
  inputs.json            source path + hash + effective JapanConfig snapshot
  parsed.json            WesternResume
  normalized.json        NormalizedResume (edit this to correct dates/bullets)
  repaired.json          NormalizedResume post-consistency-check (derived)
  validation.json        ValidationResult (derived; reporting only)
  rirekisho.json         履歴書 data (post-polish)
  shokumukeirekisho.json 職務経歴書 data (post-polish)
```

Every artifact is wrapped in an envelope carrying `kind`, `role` (`source`/`derived`), `schema_version`, `content_hash`, `inputs_hash`, `produced_at`, `produced_by` (e.g. `jpresume/0.2.0 anthropic:claude-sonnet-4-6`), `mode` (`internal`/`external`), and structured `warnings`. `inspect` surfaces status and reasons:

```
$ jpresume inspect --workspace .jpresume
Workspace: /path/to/.jpresume

Source:  /path/to/resume.md
Hash:    773a27598c3b124d…

Artifact                  Status     Produced by                     Age
─────────────────────────────────────────────────────────────────────────────
inputs.json               ✓ fresh    jpresume/0.2.0                   2m ago
parsed.json               ✓ fresh    jpresume/0.2.0                   2m ago
normalized.json           ~ stale    jpresume/0.2.0 ollama:gemma4     1h ago
repaired.json               missing
...

Issues:
  normalized.json: stale — hash changed (a1b2c3d4… → 9f8e7d6c…)
  repaired.json: missing
```

### External mode (agent driver)

LLM stages (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) can emit a prompt bundle instead of calling a provider. The driving agent performs inference with its own model and writes the response back for ingestion:

```bash
# Stage 1 — jpresume writes a prompt bundle
jpresume normalize --workspace .jpresume --external
# → .jpresume/normalize.prompt.json

# Stage 2 — agent runs its own inference and writes the response
# (any way it likes — tool call, subprocess, pasted-in JSON)

# Stage 3 — jpresume reads the response, validates, and writes the artifact
jpresume normalize --workspace .jpresume --ingest
# → .jpresume/normalized.json (mode: external)
```

On parse failure, `--ingest` writes `<stage>.error.json` with the decoder error and exits non-zero so the agent can retry with corrective context.

### Editing artifacts by hand

`normalized.json`, `rirekisho.json`, and `shokumukeirekisho.json` carry `role: source` — hand-edits survive until an upstream stage invalidates them. `repaired.json` and `validation.json` are `role: derived`; edits there are discarded the next time `repair` or `validate` runs. `inspect <artifact>` prints a banner for derived artifacts.

## Agent skill

See [Recommended usage](#recommended-usage--agent-skill) at the top of this document.

The skill lives at [`skills/japanese-resume/`](skills/japanese-resume/SKILL.md). Install with:

```bash
npx skills add KristopherGBaker/JPResume
```

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
