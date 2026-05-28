# CLI Reference

## One-shot conversion

```
jpresume convert <input.md|.docx|.pdf> [options]

Options:
  -o, --output-dir DIR          Output directory (default: same as input)
  -c, --config PATH             Config file (default: {input_dir}/jpresume_config.yaml)
  --workspace DIR               Artifact workspace (default: <outputDir>/.jpresume)
  --reconfigure                 Re-prompt for all Japan-specific fields
  --format {markdown,pdf,both}  Output format (default: both)
  --rirekisho-only              Generate only the 履歴書
  --shokumukeirekisho-only      Generate only the 職務経歴書
  --provider PROVIDER           AI provider (default: ollama)
  --model MODEL                 Model name override
  --era {western,japanese}      Date format: 2024年3月 vs 令和6年3月 (default: western)
  --target PATH                 Target-company context JSON (tailored application mode)
  --notes PATH-OR-TEXT          Free-form supplementary context (extra work/education
                                history, style preferences). Auto-detects file path
                                vs inline text. Folds into the inputs hash.
  --no-cache                    Ignore cached output and regenerate
  --strict                      Treat validation warnings as errors
  --dry-run                     Parse + normalize only, print both and exit
  -v, --verbose                 Show AI prompts/responses + critique pass counter +
                                feedback-loop accept/revert decisions
```

### Target-company context (`--target`)

Pass a JSON file to switch from neutral master-document mode to tailored application mode. All fields are optional:

```json
{
  "company_name": "株式会社〇〇",
  "role_title": "iOSエンジニア",
  "company_summary": "...",
  "job_description_excerpt": "...",
  "normalized_requirements": ["Swift", "SwiftUI"],
  "emphasis_tags": ["mobile", "consumer", "growth"],
  "candidate_interest_notes": "..."
}
```

When present, 志望動機, 職務要約, 自己PR, and role/achievement emphasis are adjusted toward the target — using only facts from the input, never fabricating. Changing the file invalidates the artifact cache.

### Free-form notes (`--notes`)

Pass extra context the LLM should know but doesn't have elsewhere — e.g. extended work or education history not on the western resume, style or emphasis preferences, corrections to ambiguous content. The flag accepts either a file path or inline text:

```bash
# Inline (best for one-line instructions)
jpresume convert resume.md --notes "Emphasize my iOS work over backend."

# File (best for multi-paragraph extras)
jpresume convert resume.md --notes notes/extras.md
```

Notes reach every LLM stage as `additional_context` in the user payload. The system prompts treat them as authoritative supplementary input — extra entries merge into experience/education; style guidance applies to tone — but never override `japan_config` on conflicts and never license fabrication. Notes fold into the inputs hash so editing them invalidates every downstream artifact (normalize, repair, both generate stages).

## Orchestration loops (one-shot quality)

`convert` runs two extra loops to narrow the gap with the interactive agent flow:

- **Validation feedback** (normalize) — after initial normalize, runs the validator; if issues exist, re-prompts with the validation output as context. Accepts only when issue count strictly decreases. Capped at 2 refinement passes.
- **Self-critique** (each generate) — after initial rirekisho/shokumukeirekisho generation, runs `JapaneseConstraintChecker` (forbidden hype phrases like 「即戦力として貢献」, 「現在」 placement in date column, duplicate first sentences between 職務要約 and 自己PR, metrics duplicated across sections, etc.). On violations, hands the current JSON + violation list back to the LLM for repair. Capped at 3 critique passes. Surviving violations are stamped onto the artifact as warnings (visible via `jpresume inspect`).

A clean run is 3 LLM calls. Worst case is ~11. Pass `--verbose` to see the per-loop pass counter and accept/revert decisions live.

## AI providers

| Provider | Flag | API key env var | Notes |
|----------|------|-----------------|-------|
| Ollama | `--provider ollama` | — | Local, default |
| OpenRouter | `--provider openrouter` | `OPENROUTER_API_KEY` | |
| OpenAI | `--provider openai` | `OPENAI_API_KEY` | |
| Anthropic | `--provider anthropic` | `ANTHROPIC_API_KEY` | |

Provider transport is handled by [Shikisha](https://github.com/KristopherGBaker/Shikisha).

## Pipeline

Each stage writes a versioned JSON artifact into `.jpresume/`. Reruns skip unchanged work via SHA-256 content hashing (covers input content + config + era + generation options + schema version).

1. **Parse** — `.md`, `.docx`, or `.pdf` → `WesternResume`. DOCX text is extracted via `SwiftDocX`. PDF text is extracted via PDFKit; scanned/image PDFs fall back to Vision OCR automatically.
2. **Config** — loads `jpresume_config.yaml` or prompts interactively; saved for reuse
3. **Normalize** — LLM structures dates, classifies bullets (achievement vs responsibility), groups skills. Falls back to deterministic parsing if LLM fails. Config dates are ground truth.
4. **Validate** — checks date ranges, overlaps, `is_current` consistency, total experience, low-confidence entries. `--strict` treats warnings as errors.
5. **Repair** — sorts chronologically, fixes overlapping dates, resolves inconsistencies, computes derived experience metrics.
6. **Adapt** — LLM translates and adapts to Japanese conventions → `RirekishoData` / `ShokumukeirekishoData`
7. **Polish + Render** — deterministic text polish, then markdown and/or PDF output

## Stepwise subcommands

For human review between stages or for use by an agent skill:

```
jpresume parse <input.md|.docx|.pdf> [--workspace .jpresume]
jpresume normalize [--workspace] [--provider] [--external | --ingest]
jpresume validate [--workspace] [--on normalized|repaired]
jpresume repair [--workspace]
jpresume generate rirekisho [--workspace] [--provider] [--era] [--target company.json] [--external | --ingest]
jpresume generate shokumukeirekisho [--workspace] [--include-side-projects] [--era] [--target company.json] [--external | --ingest]
jpresume render [rirekisho|shokumukeirekisho|both] [--workspace] [--output-dir]
jpresume inspect [<artifact>] [--workspace] [--json]
```

### Workspace layout

```
.jpresume/
  inputs.json            source path + hash + effective JapanConfig snapshot
  parsed.json            WesternResume
  normalized.json        NormalizedResume  ← safe to hand-edit
  repaired.json          NormalizedResume post-consistency-check (derived)
  validation.json        ValidationResult (derived)
  rirekisho.json         履歴書 data (post-polish)  ← safe to hand-edit
  shokumukeirekisho.json 職務経歴書 data (post-polish)  ← safe to hand-edit
```

`role: source` artifacts (`normalized.json`, `rirekisho.json`, `shokumukeirekisho.json`) survive hand-edits until an upstream stage invalidates them. `role: derived` artifacts (`repaired.json`, `validation.json`) are regenerated on each run — don't edit them.

`inspect` surfaces status and reasons:

```
$ jpresume inspect --workspace .jpresume

Artifact                  Status     Produced by                          Age
──────────────────────────────────────────────────────────────────────────────
inputs.json               ✓ fresh    jpresume/0.5.0                        2m ago
parsed.json               ✓ fresh    jpresume/0.5.0                        2m ago
normalized.json           ~ stale    jpresume/0.5.0 ollama:gemma4          1h ago
repaired.json               missing
```

### External mode

LLM stages (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) can emit a prompt bundle for an external agent to fulfil:

```bash
jpresume normalize --workspace .jpresume --external
# → writes .jpresume/normalize.prompt.json, then exits

# agent performs inference and writes response to:
# .jpresume/normalize.response.json

jpresume normalize --workspace .jpresume --ingest
# → decodes response, runs polish rules, writes .jpresume/normalized.json
```

On decode failure, `--ingest` writes `<stage>.error.json` with the decoder error and exits non-zero. See [skills/japanese-resume/references/external-mode.md](../skills/japanese-resume/references/external-mode.md) for the full protocol.
