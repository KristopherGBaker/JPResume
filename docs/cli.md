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
  --no-cache                    Ignore cached output and regenerate
  --strict                      Treat validation warnings as errors
  --dry-run                     Parse + normalize only, print both and exit
  -v, --verbose                 Show AI prompts and responses
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

## AI providers

| Provider | Flag | API key env var | Notes |
|----------|------|-----------------|-------|
| Ollama | `--provider ollama` | — | Local, default |
| Claude CLI | `--provider claude-cli` | — | Uses `claude -p` |
| Codex CLI | `--provider codex-cli` | — | Uses `codex exec` |
| OpenRouter | `--provider openrouter` | `OPENROUTER_API_KEY` | |
| OpenAI | `--provider openai` | `OPENAI_API_KEY` | |
| Anthropic | `--provider anthropic` | `ANTHROPIC_API_KEY` | |

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
