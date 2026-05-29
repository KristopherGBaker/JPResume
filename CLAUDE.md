# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

JPResume is a Swift CLI tool that converts western-style resumes (.md, .docx, or .pdf) to Japanese format (履歴書 rirekisho and 職務経歴書 shokumukeirekisho). It uses CoreGraphics for native PDF rendering with Japanese fonts (Hiragino Sans).

## Build & Test Commands

```bash
make build                     # swift build
make test                      # swift test (188 tests, 16 suites)
make lint                      # swiftlint lint
make fix                       # swiftlint lint --fix
make project                   # xcodegen generate
make install                   # build release + copy to /usr/local/bin
make bootstrap                 # mint bootstrap (install tools from Mintfile)
swift run jpresume --help      # run CLI
swift run jpresume convert examples/resume.md --dry-run  # parse + normalize only, prints both
swift run jpresume convert examples/Kristopher_Baker_Resume.md --provider anthropic --format both
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

`convert` also accepts `--notes <path-or-text>` — free-form supplementary context
from the candidate (extra work/education history not on the resume, style or
emphasis preferences, corrections). Auto-detects whether the argument is a file
path or inline text. Stored in `InputsData.user_notes` and folded into the
inputs hash so changes invalidate the entire downstream cache. Reaches every
LLM stage as `additional_context` in the user payload.

## Architecture

### Module layout (`DocPipeline` + `jpresume`)

The package has two targets:

- **`DocPipeline`** (`Sources/DocPipeline/`) — a domain-agnostic orchestration
  library. It knows nothing about resumes. It provides the typed artifact envelope
  and store, the content-hash cache, the external-mode prompt bundle protocol, the
  Shikisha provider plumbing, and the self-critique scaffolding. The store is generic
  over an `ArtifactKey` protocol; everything else is generic or plain mechanism.
  Public types: `Artifact<T>`, `ArtifactWarning`, `ArtifactSummary<Key>`, `ArtifactKey`,
  `ArtifactStore<Key>`, `ArtifactStatus`, `ArtifactStoreError`, `Severity`, `JSONCoders`,
  `AICache`/`CacheEnvelope`, `ExternalBridge`/`PromptBundle`/`ErrorBundle`,
  `ChatModelDecoder`, `ProviderFactory`, `GenerationResult<T>`, `ConstraintViolation`.
- **`jpresume`** (`Sources/JPResume/`) — the resume *instance* of that pipeline: the
  parsers, prompts, `JapanConfig`/`RirekishoData`/etc. models, validators, the
  `JapaneseConstraintChecker`, the CoreGraphics renderers, and the CLI. It conforms its
  `ArtifactKind` enum to `DocPipeline.ArtifactKey` and exposes
  `typealias ArtifactStore = DocPipeline.ArtifactStore<ArtifactKind>` so call sites read
  unchanged. Resume-specific orchestration that *uses* DocPipeline still lives here:
  `Stages`, `ArtifactHashes`, `ProducedBy`, `InputsData`, `ResumeSourceKind`.

`DocPipeline` is the candidate for graduating into its own repo later; for now it's a
local target so the boundary is compiler-enforced without the release overhead.

Pipeline: **Parse → Normalize → Validate → Adapt → Render**

1. **Input reading** (`Sources/JPResume/Parser/ResumeInputReader.swift`) accepts `.md`, `.docx`, or `.pdf`. DOCX is read through `SwiftDocX`. For PDFs, `PDFKit` text extraction is attempted first; if the result is under 100 characters (scanned/image PDF), `Vision` OCR is used as fallback.
   **Source-aware parsing** then branches by input kind:
   - markdown uses `Sources/JPResume/Parser/MarkdownParser.swift`
   - DOCX/PDF/plain text uses `Sources/JPResume/Parser/ResumeTextPreprocessor.swift` and `Sources/JPResume/Parser/PlainTextResumeParser.swift`
   The resulting `WesternResume` is advisory for non-markdown inputs; normalization also receives cleaned source text from `inputs.json`.
2. **Config** (`Sources/JPResume/Config/`) loads `jpresume_config.yaml` (Japan-specific fields: kanji name, furigana, education dates, work history) or prompts interactively, then saves for reuse via Yams.
3. **Normalize** (`Sources/JPResume/AI/ResumeNormalizer.swift`) sends `WesternResume` + `JapanConfig` + source input metadata (`source_kind`, cleaned source text, preprocessing notes) + optional `additional_context` (from `--notes`) to LLM, returns `NormalizedResume` with structured dates, classified bullets (achievement vs responsibility), and categorized skills. Falls back to deterministic parsing if LLM fails. Cached as `normalized.json` in the workspace.
   **Validation feedback loop**: after normalize, `Stages.normalize` runs validate; if issues exist, calls `ResumeNormalizer.refine` with the validation output as context, accepts only when the issue count strictly decreases (oscillation guard), capped at 2 refinement passes by default.
4. **Validate** (`Sources/JPResume/Validation/ResumeValidator.swift`) runs rule-based checks on `NormalizedResume`: date range validity, isCurrent consistency, overlapping roles, total years of experience, low confidence entries. Emits warnings; use `--strict` to treat them as errors.
5. **Adapt** (`Sources/JPResume/AI/ResumeAI.swift`) sends `NormalizedResume` + `JapanConfig` + optional `target_company_context` + optional `additional_context` to LLM, returns `RirekishoData` / `ShokumukeirekishoData` as JSON. Cached as `rirekisho.json` / `shokumukeirekisho.json` in the workspace.
   **Self-critique loop**: after each generate call, `ResumeAI.refineWithCritique` runs `JapaneseConstraintChecker`; on violations, feeds the current JSON + violation list to a critique LLM call and re-checks. Capped at 3 critique passes. Surviving violations are stamped onto the artifact as `ArtifactWarning`s.
   **Naming consistency**: when both stages run in one `convert`, `NamingContext.from(rirekisho)` extracts the company-name renderings + candidate name and threads them into the shokumukeirekisho system prompt so the two outputs agree. `generate shokumukeirekisho` also reuses an existing `rirekisho.json` when run standalone.
6. **Render** (`Sources/JPResume/Render/` + `Sources/JPResume/PDF/`) produces markdown (string interpolation templates) and PDF output (CoreGraphics).

### Intermediate Models

- `WesternResume` — raw parsed output from the deterministic parser layer. Dates are strings, bullets are flat. For DOCX/PDF/plain-text input it is advisory rather than exhaustive.
- `NormalizedResume` — canonical intermediate produced by `ResumeNormalizer`. Contains `StructuredDate` (year/month ints), `NormalizedBullet` (with `.responsibility`/`.achievement` classification), `SkillCategory` groups, and per-entry `confidence` scores.
- `TargetCompanyContext` (`Sources/JPResume/Models/TargetCompanyContext.swift`) — optional tailoring layer. Fields: `company_name`, `role_title`, `company_summary`, `job_description_excerpt`, `normalized_requirements`, `emphasis_tags`, `candidate_interest_notes`. All optional. Loaded from a JSON file via `--target`; folded into `ArtifactHashes` so the cache is invalidated when the file changes.
- `NamingContext` (`Sources/JPResume/Models/NamingContext.swift`) — per-employer name renderings + candidate name extracted from a generated `RirekishoData`. Passed to the shokumukeirekisho system prompt so both outputs use the same Japanese vs. English entity choices. Constructed automatically inside `ConvertCommand` and reused from any existing `rirekisho.json` by `generate shokumukeirekisho`.
- `GenerationResult<T>` (`Sources/DocPipeline/GenerationResult.swift`) — wrapper returned by `Stages.generateRirekisho` / `generateShokumukeirekisho`: `data` (the polished artifact), `critiquePasses` (how many critique LLM calls ran), `remainingViolations` (constraint violations the critique loop couldn't clear). The CLI commands stamp `remainingViolations` onto the artifact as `ArtifactWarning`s via `asArtifactWarnings`.
- `ConstraintViolation` (`Sources/DocPipeline/ConstraintViolation.swift`) — `{rule, field, message}` triple. The shape lives in DocPipeline; the resume-specific checker that produces them, `JapaneseConstraintChecker` (`Sources/JPResume/Validation/JapaneseConstraintChecker.swift`), mirrors the hard constraints in the rirekisho/shokumukeirekisho system prompts (forbidden hype phrases, `「現在」` in date column, duplicate first sentences between 職務要約 and 自己PR, metric duplicated across sections, etc.). Drives the self-critique loop.

### AI Provider Abstraction

Provider transport is [Shikisha](https://github.com/KristopherGBaker/Shikisha) — added as a local-path dependency (`../Shikisha`). The provider plumbing lives in **DocPipeline**: each pipeline stage builds its own `any ChatModel` via `ProviderFactory.create(provider:model:temperature:)`. Four providers are wired: `anthropic` (`AnthropicChatModel`, cacheSystem on), `openai` and `openrouter` (`OpenAIChatModel`, the latter with a different baseURL, both with `response_format: {type: json_object}` enforced), and `ollama` (`OllamaChatModel`). Default provider is `ollama`. System prompts explicitly instruct the AI to never fabricate dates or details.

`ChatModelDecoder` (also in DocPipeline) is a small generic helper that lets us call Shikisha's `asStructuredOutput<T>` against an `any ChatModel` existential — Swift can't open the existential when the result type embeds Self (as `StructuredOutputRunnable<Self, T>` does), so the wrapper opens `M: ChatModel` through a generic function parameter where only `T` appears in the return.

Normalization runs at temperature 0.2 (structured extraction). Adaptation runs at 0.3. Critique passes inherit the construction-time temperature of the same ChatModel.

### Workspace and artifacts (`Sources/DocPipeline/` + `Sources/JPResume/Pipeline/`)

The envelope, store, and external bridge are in DocPipeline; the resume-specific
`ArtifactKind`, `InputsData`, `ArtifactHashes`, `ProducedBy`, and `Stages` are in
`Sources/JPResume/Pipeline/`. Every pipeline run writes its intermediates into a workspace directory, defaulting
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

- `Artifact<T>` (`DocPipeline/Artifact.swift`) — typed envelope with `kind`, `role`
  (`"source"`/`"derived"`), `schema_version`, `content_hash`, `inputs_hash`,
  `produced_at`, `produced_by`, `mode` (`"internal"`/`"external"`), and structured
  `warnings`. Supersedes the old `CacheEnvelope<T>`.
- `ArtifactKind` (`JPResume/Pipeline/Artifact.swift`) — the resume pipeline's
  enum of artifact kinds, conforming to `DocPipeline.ArtifactKey` (supplies
  `filename`, `role`, and the legacy cache filename per kind).
- `InputsData` (`JPResume/Pipeline/Artifact.swift`) snapshots `source_kind`, `source_text`, `cleaned_text`,
  `preprocessing_notes`, and (optionally) `user_notes` (from `--notes`) so normalize
  can reason from the extracted resume text + any free-form supplementary context the
  candidate supplied. `user_notes` decodes as `nil` for older workspaces (backward
  compatible) and folds into `AICache.contentHash` so changing it invalidates
  everything downstream.
- `ArtifactStore<Key>` (`DocPipeline/ArtifactStore.swift`) — typed read/write with atomic
  `replaceItem` writes, a four-state `ArtifactStatus` (`.fresh` / `.stale(reason)` /
  `.missing` / `.invalid(reason)`), and legacy fallback driven by each `Key`'s
  `legacyCacheFilename`. jpresume uses it as `ArtifactStore<ArtifactKind>` (via the
  `ArtifactStore` typealias).
- `Stages` (`JPResume/Pipeline/Stages.swift`) — stateless wrappers around the existing
  pipeline modules. Commands chain these against one `ArtifactStore`; no
  orchestration lives in the core modules.
- `ExternalBridge` (`DocPipeline/ExternalBridge.swift`) — emits/reads prompt bundles
  with the grammar documented in `DocPipeline/ExternalBridge.swift`
  (`stage`, `artifact_kind`, `source_artifacts`, `stage_options`,
  `expected_output_format`, `response_schema`, `response_path`). `ingestResponse`
  takes a `producedBy` string so the bridge stays free of jpresume's `ProducedBy` grammar.
- `ArtifactHashes` (`JPResume/Pipeline/Artifact.swift`) — stage-aware content hashes. In particular,
  `ArtifactHashes.shokumukeirekisho` folds in `GenerationOptions`, so
  `--include-side-projects` and `--exclude-older-roles` now correctly invalidate
  the cache (fix for the pre-refactor bug).
- `ProducedBy` — canonical grammar for `produced_by`: deterministic stages emit
  `jpresume/0.6.0`, LLM stages emit `jpresume/0.6.0 anthropic:claude-sonnet-4-6`,
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
- AI structured-output decoding goes through Shikisha's `asStructuredOutput` (system message + JSON-object response_format on OpenAI; prompt-only adherence on Anthropic with `cacheSystem: true`). ExternalBridge keeps a fence-tolerant JSON extractor inline since it's the only consumer of that path post-Shikisha refactor.
- The one-shot `convert` path narrows the quality gap with the agent-driven external flow through three orchestration loops: a validation feedback loop on normalize (max 2 refinement passes, oscillation guard), a self-critique loop on each generate stage (max 3 critique passes, surviving violations stamped as `ArtifactWarning`s), and shared `NamingContext` between rirekisho and shokumukeirekisho. Per-stage cost ceiling: ~11 LLM calls worst case, ~3 for a clean run.
- `generate rirekisho` and `generate shokumukeirekisho` strictly require `repaired.json`. They refuse silent fallback to `normalized.json` so the review loop isn't bypassable; `convert` runs the full chain internally, so humans lose nothing.
- `inspect` surfaces `ArtifactStatus` reasons (`stale — hash changed (a1b2…)`, `invalid — schema version mismatch`) and flags artifacts with `role: "derived"` so hand-edits aren't silently discarded.
