# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JPResume is a Swift CLI tool that converts western-style resumes (.md, .docx, or .pdf) to Japanese format (履歴書 rirekisho and 職務経歴書 shokumukeirekisho). It uses CoreGraphics for native PDF rendering with Japanese fonts (Hiragino Sans).

## Build & Test Commands

```bash
make build                     # swift build
make test                      # swift test (155 tests, 13 suites)
make lint                      # swiftlint lint
make fix                       # swiftlint lint --fix
make project                   # xcodegen generate
make install                   # build release + copy to /usr/local/bin
make bootstrap                 # mint bootstrap (install tools from Mintfile)
swift run jpresume --help      # run CLI
swift run jpresume convert examples/resume.md --dry-run  # parse + normalize only, prints both
swift run jpresume convert examples/Kristopher_Baker_Resume.md --provider claude-cli --format both
```

## CLI surface

Two orchestration modes share the same underlying pipeline:

- **`convert <input.md|.docx|.pdf>`** — one-shot end-to-end run (unchanged behavior).
- **Stepwise subcommands** — `parse`, `normalize`, `validate`, `repair`, `generate
  rirekisho`, `generate shokumukeirekisho`, `render`, `inspect`. Each reads / writes
  artifacts inside a workspace so humans or agents can pause, review, and resume
  between stages.

LLM stages (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) also
accept `--external` (write a prompt bundle and exit; caller performs inference) and
`--ingest` (read the caller's response file and write the artifact).

`generate rirekisho` and `generate shokumukeirekisho` accept `--target <file.json>`
(`TargetCompanyContext`) to switch from neutral master-document mode to tailored
application mode (adjusts 志望動機, 職務要約, 自己PR, role/achievement emphasis).
`convert` also accepts `--target`. Changing the target file invalidates the artifact cache.

## Architecture

Pipeline: **Parse → Normalize → Validate → Adapt → Render**

1. **Input reading** (`Sources/JPResume/Parser/ResumeInputReader.swift`) accepts `.md`, `.docx`, or `.pdf`. DOCX is read through `SwiftDocX`. For PDFs, `PDFKit` text extraction is attempted first; if the result is under 100 characters (scanned/image PDF), `Vision` OCR is used as fallback.
   **Source-aware parsing** then branches by input kind:
   - markdown uses `Sources/JPResume/Parser/MarkdownParser.swift`
   - DOCX/PDF/plain text uses `Sources/JPResume/Parser/ResumeTextPreprocessor.swift` and `Sources/JPResume/Parser/PlainTextResumeParser.swift`
   The resulting `WesternResume` is advisory for non-markdown inputs; normalization also receives cleaned source text from `inputs.json`.
2. **Config** (`Sources/JPResume/Config/`) loads `jpresume_config.yaml` (Japan-specific fields: kanji name, furigana, education dates, work history) or prompts interactively, then saves for reuse via Yams.
3. **Normalize** (`Sources/JPResume/AI/ResumeNormalizer.swift`) sends `WesternResume` + `JapanConfig` + source input metadata (`source_kind`, cleaned source text, preprocessing notes) to LLM, returns `NormalizedResume` with structured dates, classified bullets (achievement vs responsibility), and categorized skills. Falls back to deterministic parsing if LLM fails. Cached to `.normalized_cache.json`.
4. **Validate** (`Sources/JPResume/Validation/ResumeValidator.swift`) runs rule-based checks on `NormalizedResume`: date range validity, isCurrent consistency, overlapping roles, total years of experience, low confidence entries. Emits warnings; use `--strict` to treat them as errors.
5. **Adapt** (`Sources/JPResume/AI/ResumeAI.swift`) sends `NormalizedResume` + `JapanConfig` to LLM, returns `RirekishoData` / `ShokumukeirekishoData` as JSON. Cached to `.rirekisho_cache.json` / `.shokumukeirekisho_cache.json`.
6. **Render** (`Sources/JPResume/Render/` + `Sources/JPResume/PDF/`) produces markdown (string interpolation templates) and PDF output (CoreGraphics).

### Intermediate Models

- `WesternResume` — raw parsed output from the deterministic parser layer. Dates are strings, bullets are flat. For DOCX/PDF/plain-text input it is advisory rather than exhaustive.
- `NormalizedResume` — canonical intermediate produced by `ResumeNormalizer`. Contains `StructuredDate` (year/month ints), `NormalizedBullet` (with `.responsibility`/`.achievement` classification), `SkillCategory` groups, and per-entry `confidence` scores.
- `TargetCompanyContext` (`Sources/JPResume/Models/TargetCompanyContext.swift`) — optional tailoring layer. Fields: `company_name`, `role_title`, `company_summary`, `job_description_excerpt`, `normalized_requirements`, `emphasis_tags`, `candidate_interest_notes`. All optional. Loaded from a JSON file via `--target`; folded into `ArtifactHashes` so the cache is invalidated when the file changes.

### AI Provider Abstraction

`AIProvider` protocol with `chat(system:user:temperature:) async throws -> String`. Six implementations using URLSession (API providers) or Process (CLI providers). Default provider is `ollama`. System prompts explicitly instruct the AI to never fabricate dates or details.

Normalization runs at temperature 0.2 (structured extraction). Adaptation runs at the default temperature 0.3.

### Workspace and artifacts (`Sources/JPResume/Pipeline/`)

Every pipeline run writes its intermediates into a workspace directory, defaulting
to `<outputDir>/.jpresume/` (overridable via `--workspace`):

```
.jpresume/
  inputs.json           # source path + content hash + effective JapanConfig + source kind/text metadata
  parsed.json           # WesternResume (role: source)
  normalized.json       # NormalizedResume (role: source — agent edit target)
  repaired.json         # NormalizedResume post-consistency-check (role: derived)
  validation.json       # ValidationResult (role: derived)
  rirekisho.json        # RirekishoData post-polish (role: source)
  shokumukeirekisho.json
  rirekisho.md / .pdf
  shokumukeirekisho.md / .pdf
  # external-mode scratch (LLM stages only):
  <stage>.prompt.json   # written by --external
  <stage>.response.json # supplied by the caller
  <stage>.error.json    # written when --ingest fails
```

Key types:

- `Artifact<T>` (`Pipeline/Artifact.swift`) — typed envelope with `kind`, `role`
  (`"source"`/`"derived"`), `schema_version`, `content_hash`, `inputs_hash`,
  `produced_at`, `produced_by`, `mode` (`"internal"`/`"external"`), and structured
  `warnings`. Supersedes the old `CacheEnvelope<T>`.
- `InputsData` now snapshots `source_kind`, `source_text`, `cleaned_text`, and
  `preprocessing_notes` so normalize can reason from the extracted resume text directly.
- `ArtifactStore` (`Pipeline/ArtifactStore.swift`) — typed read/write with atomic
  `replaceItem` writes, a four-state `ArtifactStatus` (`.fresh` / `.stale(reason)` /
  `.missing` / `.invalid(reason)`), and legacy fallback for
  `.{normalized,rirekisho,shokumukeirekisho}_cache.json` (one-release window).
- `Stages` (`Pipeline/Stages.swift`) — stateless wrappers around the existing
  pipeline modules. Commands chain these against one `ArtifactStore`; no
  orchestration lives in the core modules.
- `ExternalBridge` (`Pipeline/ExternalBridge.swift`) — emits/reads prompt bundles
  with the grammar documented in `Pipeline/ExternalBridge.swift`
  (`stage`, `artifact_kind`, `source_artifacts`, `stage_options`,
  `expected_output_format`, `response_schema`, `response_path`).
- `ArtifactHashes` — stage-aware content hashes. In particular,
  `ArtifactHashes.shokumukeirekisho` folds in `GenerationOptions`, so
  `--include-side-projects` and `--exclude-older-roles` now correctly invalidate
  the cache (fix for the pre-refactor bug).
- `ProducedBy` — canonical grammar for `produced_by`: deterministic stages emit
  `jpresume/0.4.1`, LLM stages emit `jpresume/0.4.1 anthropic:claude-sonnet-4-6`,
  external mode emits `claude-code/external <model>`.

### Legacy cache format

Workspaces are forward-only. On first run after upgrading, the store reads the
legacy cache paths (`.{normalized,rirekisho,shokumukeirekisho}_cache.json`) if the
workspace artifact is missing, then re-writes in the new envelope format. Legacy
fallback will be removed in a future release.

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
- `generate rirekisho` and `generate shokumukeirekisho` strictly require `repaired.json`. They refuse silent fallback to `normalized.json` so the review loop isn't bypassable; `convert` runs the full chain internally, so humans lose nothing.
- `inspect` surfaces `ArtifactStatus` reasons (`stale — hash changed (a1b2…)`, `invalid — schema version mismatch`) and flags artifacts with `role: "derived"` so hand-edits aren't silently discarded.
