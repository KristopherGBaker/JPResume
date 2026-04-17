# jpresume stepwise/agent mode — final plan

## 1. Architecture overview

The current pipeline is already cleanly modularized (`MarkdownParser`, `ResumeNormalizer`, `ResumeValidator`, `ResumeConsistencyChecker`, `ResumeAI`, `JapanesePolishRules`, `MarkdownRenderer`, PDF renderers). `ConvertCommand.run()` is the only caller, binding them with in-memory values. The change is extraction, not rewrite:

```
┌──────────────┐   writes   ┌────────────────┐   reads   ┌──────────────┐
│  Stage fns   │ ─────────▶ │ ArtifactStore  │ ─────────▶│  Stage fns   │
│  (stateless) │            │ (.jpresume/)   │           │  (stateless) │
└──────────────┘            └────────────────┘           └──────────────┘
       ▲                                                         │
       │                                                         ▼
┌──────┴───────────────────────────────────────────────────────────────┐
│  Orchestrators: ConvertCommand (batch), per-stage subcommands (step) │
└──────────────────────────────────────────────────────────────────────┘
```

Stages are **stateless**, not pure — LLM stages are async and network-side-effecting. What matters is that they carry no state between calls and are deterministic in their inputs for a given model.

Three LLM stages (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) gain an external mode: jpresume emits a prompt bundle, the driving agent performs inference with its own model, jpresume ingests the response. Non-LLM stages (`parse`, `validate`, `repair`, `render`, `inspect`) are identical whether a human or an agent is driving.

Default workspace: `<outputDir>/.jpresume/`, overridable via `--workspace`.

```
.jpresume/
  inputs.json                          # source paths + hashes + effective config snapshot
  parsed.json                          # WesternResume
  normalized.json                      # NormalizedResume (post-normalize)
  repaired.json                        # NormalizedResume (post-ConsistencyChecker)
  validation.json                      # ValidationResult snapshot (derived, reporting only)
  rirekisho.json                       # RirekishoData (post-polish)
  shokumukeirekisho.json
  rirekisho.md / .pdf
  shokumukeirekisho.md / .pdf
  # external-mode only:
  normalize.prompt.json / .response.json / .error.json
  rirekisho.prompt.json / .response.json / .error.json
  shokumukeirekisho.prompt.json / .response.json / .error.json
```

### Note on `repaired.json` naming

The `repair` stage technically does more than repair: it runs `ResumeConsistencyChecker`, which applies repairs, computes derived experience metrics, and annotates timeline warnings. We considered `checked`, `consistent`, `canonical`, `resolved`, `finalized`. Keeping `repaired.json` because (a) the command is `repair` and matching artifact-to-command is valuable, and (b) the primary *public* effect is applying repairs; the annotations are secondary. Revisit if the stage grows materially.

## 2. CLI commands

All step commands share `--workspace`, `--provider`, `--model`, `--verbose`, `--no-cache`. LLM stages additionally support `--external` and `--ingest`.

| Command | Reads | Writes | LLM? |
|---|---|---|---|
| `jpresume parse <input.md>` | markdown, config | `inputs.json`, `parsed.json` | no |
| `jpresume normalize` | `parsed.json`, `inputs.json` | `normalized.json` | yes |
| `jpresume validate [--on normalized\|repaired]` | repaired.json if present, else normalized.json | `validation.json` | no |
| `jpresume repair` | `normalized.json` | `repaired.json` | no |
| `jpresume generate rirekisho` | **`repaired.json`** (required), `inputs.json` | `rirekisho.json` | yes |
| `jpresume generate shokumukeirekisho` | **`repaired.json`** (required), `inputs.json` | `shokumukeirekisho.json` | yes |
| `jpresume render [rirekisho\|shokumukeirekisho\|both]` | `*.json` | `.md`, `.pdf` | no |
| `jpresume inspect [artifact]` | any artifact | stdout | no |
| `jpresume convert <input.md>` | markdown | everything | yes (uses configured provider) |

Input-precedence rules worth calling out:

- **`validate`** defaults to `repaired.json` when it exists, otherwise `normalized.json`. Rationale: repaired is strictly normalized + repairs applied, so it's the more correct input to validate. Override with `--on normalized` or `--on repaired`.
- **`generate rirekisho` / `generate shokumukeirekisho`** strictly require `repaired.json`. If missing, error with `"run 'jpresume repair' first"`. Silent fallback to `normalized.json` would let users skip the review loop — the whole point of stepwise mode. `convert` runs the full chain internally, so no real-world ergonomic loss.
- **`repair`** recomputes from `normalized.json` every run. It never reads `validation.json`. `validation.json` is a reporting artifact for humans and agents; no stage consumes it. This keeps the dependency graph simple.

LLM-stage flag semantics:

- Default: call the configured `AIProvider` end-to-end (current behavior).
- `--external`: write `<stage>.prompt.json` to the workspace and exit 0. No LLM call.
- `--ingest`: read `<stage>.response.json`, validate, extract JSON, run polish as applicable, write the artifact. On failure write `<stage>.error.json` and exit non-zero.

Examples:

```bash
# Agent-driven, external LLM
jpresume parse resume.md --workspace .work
jpresume normalize --workspace .work --external
jpresume normalize --workspace .work --ingest
jpresume repair --workspace .work
jpresume validate --workspace .work
jpresume inspect validation --workspace .work        # agent reviews warnings
# agent edits .work/normalized.json, re-runs repair + validate
jpresume generate rirekisho --workspace .work --external
jpresume generate rirekisho --workspace .work --ingest
jpresume generate shokumukeirekisho --workspace .work --external --include-side-projects
jpresume generate shokumukeirekisho --workspace .work --ingest
jpresume render both --workspace .work

# Human-driven, stepwise, jpresume does inference
jpresume parse resume.md --workspace .work
jpresume normalize --workspace .work --provider claude-cli
jpresume repair --workspace .work
jpresume validate --workspace .work
jpresume generate rirekisho --workspace .work
jpresume render rirekisho --workspace .work

# One-shot (unchanged)
jpresume convert resume.md --provider claude-cli --format both
```

## 3. Artifacts

Every artifact extends today's `CacheEnvelope`:

```swift
struct Artifact<T: Codable>: Codable {
    let kind: String                 // "parsed" | "normalized" | ...
    let role: String                 // "source" | "derived"
    let schemaVersion: String        // reuse AICache.schemaVersion
    let contentHash: String          // hash of logical inputs to this stage
    let inputsHash: String           // hash of inputs.json (source markdown + config)
    let producedAt: String           // ISO-8601
    let producedBy: String           // see grammar below
    let mode: String                 // "internal" | "external" (metadata only)
    let warnings: [Warning]          // structured; see below
    let data: T
}

struct Warning: Codable {
    let severity: String             // "info" | "warning" | "error"
    let field: String?
    let message: String
}
```

`role: "derived"` marks artifacts (currently `validation.json`) that are always regeneratable and where hand-edits are meaningless. `inspect` prints a visible banner when viewing derived artifacts instead of injecting non-standard JSON comments that would break strict parsers.

**Hash philosophy: semantic, not reproductive.**

`contentHash` = `sha256(upstream_artifact_hashes + stage_options + prompt_version + schema_version)`. Provider, model, and mode are **not** in the hash — they're provenance metadata. Rationale:

- An artifact represents "these inputs with this prompt version should produce this semantic result."
- Switching mode or model shouldn't force churn. If an agent regenerates with a different external model, the new artifact replaces the old one in the same workspace — no semantic ambiguity.
- `--no-cache` is the explicit escape hatch when someone genuinely wants to regenerate.
- `inputsHash` continues to use today's `AICache.contentHash(markdownContent:configData:)`.
- Folding `GenerationOptions` into the shokumukeirekisho hash fixes an existing bug where `--include-side-projects` doesn't invalidate the cache.

**`producedBy` grammar.** Parseable, consistent across internal/external:

```
<actor>/<version> [<provider>:<model>]
```

Examples:
- `jpresume/0.2.0 ollama:llama3.2`
- `jpresume/0.2.0 anthropic:claude-sonnet-4-6`
- `claude-code/external claude-sonnet-4-6`
- `jpresume/0.2.0` (deterministic stage, no model)

**Cache-hit logs carry provenance.** When a stage hits its cache it prints `Using cached normalized resume (claude-code/external claude-sonnet-4-6, 2h ago)` rather than a bare "cached" message.

**Warning severities.** `ValidationSeverity` extended from `{warning, error}` to `{info, warning, error}`. Artifact `warnings` are structured `Warning` values so `inspect` can filter by severity and agents can make decisions without string-parsing messages.

Prompt bundle:

```json
{
  "stage": "normalize",
  "artifact_kind": "normalized",
  "workspace": ".jpresume",
  "source_artifacts": ["parsed.json", "inputs.json"],
  "stage_options": {
    "include_side_projects": false,
    "include_older_irrelevant_roles": true,
    "era": "western"
  },
  "system": "...",
  "user": "...",
  "temperature": 0.2,
  "expected_output_format": "json-only",
  "response_schema": { },
  "response_path": ".jpresume/normalize.response.json"
}
```

`stage_options` gives the external agent full execution context — the same options that shaped the system/user prompts, so the agent can reason about them and reproduce across runs. `response_schema` ships prose-only for MVP (as `SystemPrompts.swift` already describes); hand-written JSON Schema per Codable type can come later if ingest failures cluster.

Artifact roles:

| Artifact | Role | Agent-editable? |
|---|---|---|
| `inputs.json` | Source; includes effective `JapanConfig` snapshot | No (regenerated by `parse`) |
| `parsed.json` | Source, deterministic | In principle, low value |
| `normalized.json` | Source; primary agent edit target for date/overlap fixes | **Yes** — the main collaboration surface |
| `repaired.json` | Derived from normalized | No (regenerated by `repair`) |
| `validation.json` | Derived reporting artifact; no stage consumes it | **No** — `role: "derived"`, edits don't stick |
| `rirekisho.json` / `shokumukeirekisho.json` | Source; post-polish; editable for field tweaks | **Yes** — manual edits survive until upstream regen |
| `*.md` / `*.pdf` | Build outputs | No |
| `*.prompt.json` / `*.response.json` | External-mode scratch; `*.error.json` on failed ingest | Response file, yes |

## 4. Internal refactor

Principle: no behavioral rewrites to core modules. Light interface changes are fine where they simplify stage extraction or error surfacing — don't lock yourself into "no changes" if a small tweak clearly helps.

1. **`Sources/JPResume/Pipeline/Artifact.swift`** — envelope type above, including structured `Warning`.

2. **`Sources/JPResume/Pipeline/ArtifactStore.swift`** — typed read/write, atomic writes (temp + rename), reuses `CacheEnvelope` / SHA-256 from `AICache`. First-class artifact status API:

   ```swift
   enum ArtifactStatus: Equatable {
       case fresh
       case stale(reason: String)         // exists, parses, but upstream changed
       case missing                       // file doesn't exist
       case invalid(reason: String)       // exists but unreadable / schema mismatch / version mismatch
   }

   struct ArtifactStore {
       let root: URL
       func write<T: Codable>(_ value: T, kind: ArtifactKind, hashes: Hashes,
                              producedBy: String, mode: String, warnings: [Warning]) throws
       func read<T: Codable>(_ kind: ArtifactKind, as: T.Type) throws -> Artifact<T>
       func status(_ kind: ArtifactKind) -> ArtifactStatus
       func list() -> [ArtifactSummary]
   }
   ```

   Agents need all four states: "doesn't exist yet" vs "exists but outdated" vs "exists but corrupted" drive different remediation. Supports reading legacy `.{normalized,rirekisho,shokumukeirekisho}_cache.json` for one release.

3. **`Sources/JPResume/Pipeline/Stages.swift`** — stateless namespace wrapping existing functions. No behavior change:

   ```swift
   enum Stages {
       static func parse(markdown: String) -> WesternResume
       static func normalize(_:config:provider:verbose:) async throws -> NormalizedResume
       static func validate(_:) -> ValidationResult
       static func repair(_:) -> NormalizedResume
       static func generateRirekisho(...) async throws -> RirekishoData
       static func generateShokumukeirekisho(...) async throws -> ShokumukeirekishoData
       static func polish<T>(_:derived:) -> T
       static func renderMarkdown(...) -> String
       static func renderPDF(...) throws
   }
   ```

4. **`Sources/JPResume/Pipeline/ExternalBridge.swift`** — two helpers used only by LLM stage commands:

   ```swift
   enum ExternalBridge {
       static func emitPrompt(stage: String, kind: ArtifactKind,
                              workspace: URL, sourceArtifacts: [String],
                              stageOptions: [String: Any],
                              system: String, user: String,
                              temperature: Double, to: URL) throws
       static func readResponse(stage: String, at: URL) throws -> String
   }
   ```

5. **`Sources/JPResume/CLI/Stage*Command.swift`** — one `AsyncParsableCommand` per stage. LLM stages branch on `--external` / `--ingest` / default. Each ~40–60 lines.

6. **`Sources/JPResume/CLI/InspectCommand.swift`** — structured summaries, not raw dumps. Defined behavior:

   - `inspect` (no args) → workspace status: source path, config hash, artifact table with `ArtifactStatus` + reasons, warning counts by severity
   - `inspect <artifact>` → per-kind concise summary (role list + dates, validation issues grouped by severity, derived experience metrics, key fields). Banner for `role: "derived"` artifacts explaining they're regenerated.
   - `inspect <artifact> --json` → raw artifact dump

7. **Refactor `ConvertCommand`** — becomes ~30 lines that chain `Stages.*` calls against one `ArtifactStore`. All caching logic moves to the store. `convert` always runs internal mode (the skill wraps external mode itself).

Small interface changes to core that fall out of this:

- `ValidationSeverity` gains `.info`.
- `ValidationResult` produces structured `Warning` values directly, so stages can pass them into the envelope without re-wrapping.

No behavioral changes to `ResumeAI`, `ResumeNormalizer`, `ResumeValidator`, `ResumeConsistencyChecker`, `JapanesePolishRules`, `MarkdownRenderer`, PDF renderers, or `AIProvider` implementations.

## 5. MVP scope

Ship in this order — each step leaves `main` green:

1. `ArtifactStore` + `Artifact<T>` + structured `Warning` + legacy-cache fallback + `status()` API with four states.
2. `Stages` namespace (trivial wrappers).
3. **Refactor `ConvertCommand` onto the new rails first.** Once `convert` uses `Stages` + `ArtifactStore`, subcommands become thin wrappers and there's no risk of maintaining two orchestration paths.
4. Subcommands: `parse`, `normalize`, `validate`, `repair`, `generate`, `render`, `inspect`. All seven are MVP — `validate` and `repair` are the whole point of stepwise review.
5. `--external` / `--ingest` on the three LLM stages.

Deferred:

- JSON Schema emission in prompt bundles (prose-only for MVP).
- Field-level partial regeneration (e.g. "just 自己PR"). Workaround: edit the JSON artifact and re-run `render`.
- `--from-stage` resume flag on `convert`.
- Workspace GC, artifact diffing, multi-run comparison.

~600 LOC added, ~100 LOC removed from `ConvertCommand`.

## 6. Migration / rollout

Four PRs, each shippable independently:

1. **Artifact layer.** `ArtifactStore`, `Artifact<T>`, structured `Warning`, `ArtifactStatus`, legacy fallback. No CLI changes. Tests pass.
2. **Stages + `convert` refactor.** `ConvertCommand` uses `Stages` + `ArtifactStore`. Behavior identical; `GenerationOptions` hash bug fixed; `ValidationSeverity` gains `.info`.
3. **Stepwise subcommands.** `parse`, `normalize`, `validate`, `repair`, `generate`, `render`, `inspect`. Internal-mode LLM only. `generate` enforces the `repaired.json` requirement.
4. **External mode.** `--external` / `--ingest` on LLM stages. Prompt bundle format with `artifact_kind` / `workspace` / `source_artifacts` / `stage_options` / `expected_output_format`, `*.error.json` on failed ingest, `producedBy` grammar surfaced in cache-hit logs.

## 7. Risks / tradeoffs

- **Agent output non-conformance.** Today `ResumeNormalizer` has a built-in retry loop with corrective prompting; in external mode that loop lives in the skill. Mitigation: `--ingest` writes a structured `*.error.json` with decoder path + message so the skill retries informed, not blind.
- **Stale artifacts after human edits.** Editing `normalized.json` invalidates downstream hashes; `generate` correctly regenerates. Mitigation: `inspect` surfaces `ArtifactStatus` reasons from `ArtifactStore.status()`.
- **Workspace collision.** Two `jpresume` processes in one workspace can stomp. Mitigation: atomic temp+rename writes; add a lockfile only if real collisions appear.
- **Fabrication.** External-mode agents can fabricate dates in `normalized.json`. Existing validator catches gross issues. Mitigation: optional `--require-clean-validation` flag on `generate`.
- **Schema drift.** Bumping `schemaVersion` invalidates all artifacts. Same cost as today, wider blast radius. Acceptable.
- **Derived artifacts mistaken for editable.** A user might edit `validation.json` expecting it to stick. Mitigation: `role: "derived"` in the envelope, `inspect` banner, clear naming. No non-standard JSON comments.
- **Prose schemas may confuse strict-JSON agents.** If ingest failures cluster, add JSON Schema emission. Don't front-load.
- **`claude-cli` / `codex-cli` providers now overlap with external mode.** They stay for humans running jpresume from a terminal; agent skills prefer `--external` to avoid double round-trips.

## 8. Next implementation steps

1. `Sources/JPResume/Pipeline/` directory: `Artifact.swift` (with `Warning`, `role`), `ArtifactStore.swift` (with `ArtifactStatus`), `Stages.swift`.
2. Port `CacheEnvelope` → `Artifact<T>` with new fields; read-old-path fallback for the three existing caches.
3. Extend `ValidationSeverity` with `.info`; update `ResumeValidator` to emit structured `Warning` values directly.
4. Refactor `ConvertCommand.run()` to orchestrate `Stages.*` against an `ArtifactStore`; fold `GenerationOptions` into the shokumukeirekisho hash; include effective `JapanConfig` snapshot in `inputs.json`. Verify all 43 tests pass.
5. Add `ParseCommand`, `NormalizeCommand`, `ValidateCommand` (with `--on normalized|repaired`), `RepairCommand`, `GenerateCommand` (subcommands `rirekisho`/`shokumukeirekisho`, enforcing `repaired.json`), `RenderCommand`, `InspectCommand`. Register in `JPResume.subcommands`. `InspectCommand` implements the three defined behaviors.
6. Add `--external` / `--ingest` to `NormalizeCommand` and `GenerateCommand`. Implement `ExternalBridge` with the enriched prompt bundle including `stage_options`.
7. Define `producedBy` grammar as a shared helper; surface it + age in cache-hit log messages across all stages.
8. Tests: per-subcommand integration test against `examples/resume.md` with a stub `AIProvider`; full-sequence test asserting parity with `convert`; external-mode test that writes a canned response and runs `--ingest`; status test that edits an upstream artifact and asserts `stale` downstream + `missing` for absent artifacts + `invalid` for corrupted files; `generate` without `repaired.json` returns the expected error.
9. Update `CLAUDE.md` architecture section and add a "Stepwise / agent workflow" section to the README.
