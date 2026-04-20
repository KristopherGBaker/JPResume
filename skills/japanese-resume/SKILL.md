---
name: japanese-resume
description: Create and iteratively refine Japanese-style resumes — 履歴書 (rirekisho) and 職務経歴書 (shokumukeirekisho) — from a western resume (.md or .pdf) using the JPResume CLI. Use when the user mentions Japanese resumes, rirekisho, shokumukeirekisho, applying to Japanese companies, or refining an existing .jpresume workspace.
---

# Japanese Resume Builder (JPResume)

Drive the `jpresume` CLI stage-by-stage to turn a western resume source (`.md` or `.pdf`) into a Japanese 履歴書 and 職務経歴書. You (the agent) act as the LLM for the normalize and generate stages via `--external` mode, so you can review, refine, and catch fabrications inline.

Tool: `jpresume` (Swift CLI from the JPResume repo; typically installed at `/usr/local/bin/jpresume` via `make install`).

## Core principles

1. **External mode by default.** You produce the JSON for `normalize`, `generate rirekisho`, and `generate shokumukeirekisho`. Don't route through `--provider claude-cli` unless the user asks for autonomous/batch. Rationale: you can inspect the prompt, reason about edge cases, and fix mistakes without a round-trip to another CLI.
2. **Pause after validate.** Run parse → normalize → repair → validate automatically. Stop there, surface warnings to the user, fix issues (either by editing `normalized.json` or asking the user for ground truth), then continue to generate + render after confirmation.
3. **Never fabricate.** Dates, employers, titles, and achievements must come from the source resume text or `jpresume_config.yaml`. If something is missing, ask. The normalizer's system prompt is explicit about this — follow it.
4. **Ground-truth from config.** `jpresume_config.yaml` (kanji name, furigana, address, education/work timelines, certifications) is authoritative. The source resume text is secondary for dates when the config disagrees.
5. **Hand-edit `role: source` artifacts freely, never `role: derived`.** `normalized.json`, `rirekisho.json`, `shokumukeirekisho.json` are editable and survive until upstream regen. `repaired.json` and `validation.json` are regenerated every run.

## When to use this skill

- User asks to generate, update, or refine a 履歴書 / 職務経歴書 / rirekisho / shokumukeirekisho
- User is applying to Japanese companies and needs JP-format CVs
- User points at a markdown or PDF resume and wants Japanese output
- User wants to iterate on an existing `.jpresume/` workspace (review warnings, fix dates, regenerate a section)

## Preflight checklist

Before the first stage:

1. Verify the CLI: `jpresume --version`. If missing, install from the JPResume repo root with `make install`.
2. Locate the input resume (`.md` or `.pdf`) and the `jpresume_config.yaml`. Default layout is `<dir>/resume.md` (or `resume.pdf`) + `<dir>/jpresume_config.yaml`. PDF inputs are supported natively — text-layer PDFs are read directly; scanned/image PDFs fall back to Vision OCR automatically.
3. If the config is missing, see [references/config-schema.md](references/config-schema.md) and draft one with the user — do NOT run `jpresume parse` expecting interactive prompts (they only work on a TTY you can't drive).
4. Pick a workspace directory. Default is `<input-dir>/.jpresume/`. Use `--workspace` to override when running multiple variants.

## Operating modes

| Mode | Use when | How |
|------|----------|-----|
| **External (default)** | Collaborating live with the user | `jpresume <stage> --external`, you produce JSON, `--ingest` reads it |
| **Internal (provider)** | User asks to "just run it" or wants a one-shot from CI | `jpresume convert resume.md --provider claude-cli --format both` |
| **Hybrid** | Some stages external, some internal | Mix on a per-stage basis |

## External-mode protocol

Every LLM stage (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) uses the same three-step pattern. Full details in [references/external-mode.md](references/external-mode.md).

1. **Emit**: `jpresume <stage> --workspace <ws> --external` writes `<ws>/<stage>.prompt.json` and exits.
2. **Respond**: Read the bundle with the `Read` tool. Follow the `system` field's instructions to produce JSON that matches the schema described in it. The `user` field is the payload (parsed resume + config + source input metadata for `normalize`, or repaired resume + config for generate stages). Write the raw JSON body to the path given in `response_path` (typically `<ws>/<stage>.response.json`) with the `Write` tool.
3. **Ingest**: `jpresume <stage> --workspace <ws> --ingest` decodes the response, runs polish rules, and writes the artifact. On failure it writes `<stage>.error.json` — read it, fix the issue, re-write the response, re-run `--ingest`.

Return ONLY JSON in the response file. No prose, no markdown commentary. Code fences are tolerated but unnecessary.

## Stage walk-through

### 1. Parse (deterministic, no LLM)

```bash
jpresume parse <input.md|.pdf> --workspace <ws>
```

Accepts `.md` or `.pdf`. PDF text is extracted automatically (PDFKit for text-layer PDFs; Vision OCR for scanned/image PDFs). Markdown input uses the markdown parser directly. PDF/plain-text input is preprocessed into cleaned text, then parsed through the plain-text parser. Produces `inputs.json` (source path + hash + effective `JapanConfig` snapshot + source text metadata) and `parsed.json` (a `WesternResume`). Parsing is deterministic, but for PDF/OCR input it is advisory rather than exhaustive — normalize also sees the cleaned source text.

### 2. Normalize (LLM — you drive)

```bash
jpresume normalize --workspace <ws> --external
# Read <ws>/normalize.prompt.json
# Write JSON to <ws>/normalize.response.json
jpresume normalize --workspace <ws> --ingest
```

Output: `normalized.json` — structured dates (year/month ints), bullets classified as `achievement` or `responsibility`, skills grouped into categories, per-entry `confidence`. Use `JapanConfig` dates as ground truth when they disagree with free-text in the source resume.

Read `system` for the full contract. Key rules:
- Never invent dates. If uncertain, set `confidence` below 0.8 on that entry.
- Every bullet needs `"category": "achievement"` or `"category": "responsibility"` (not `type:`).
- Skill categories (use these names): `Languages`, `Frameworks`, `Databases`, `Infrastructure`, `Tools`, `Other`.
- Top-level output must include `"repairs": []` (empty array — repairs are added by the repair stage, not here).

### 3. Repair (deterministic)

```bash
jpresume repair --workspace <ws>
```

Sorts roles chronologically, reconciles overlapping dates, resolves `is_current` inconsistencies, computes derived experience metrics. Always re-run after editing `normalized.json`.

### 4. Validate + **pause here**

```bash
jpresume validate --workspace <ws>
jpresume inspect --workspace <ws>
```

`validate` writes `validation.json` with `info`/`warning`/`error` entries. `inspect` prints a human-friendly summary. **Stop and show the warnings to the user.**

Common warnings and how to fix:

| Warning | Fix |
|---------|-----|
| Overlapping roles | Usually legitimate (concurrent roles). If not, edit `normalized.json` dates and re-run `repair`. |
| Low-confidence entry | Confirm date/detail with user. Edit `normalized.json` with correct value, set `confidence: "high"`. Re-run `repair`. |
| `is_current` mismatch | Check with user if role is still active. Edit `normalized.json`. |
| Gap > 6 months | Confirm with user. If intentional (career break, study), optionally add a `work_japanese` entry in `jpresume_config.yaml` — then re-run `parse` + `normalize`. |
| Total years < expected | Likely missing older roles. Check `work_japanese` in config. |

After fixes: `jpresume repair --workspace <ws> && jpresume validate --workspace <ws>`.

Only continue to step 5 after the user confirms the warnings are understood or resolved.

### 5. Generate rirekisho (LLM — you drive)

```bash
jpresume generate rirekisho --workspace <ws> --external
# Read, respond, ingest as above
jpresume generate rirekisho --workspace <ws> --ingest
```

Output: `rirekisho.json` (履歴書 data post-polish). The 履歴書 is a grid-form: name, photo slot, education and work timelines, licenses, 志望動機, 本人希望記入欄.

Ask user about `--era` before running:
- `--era western` (default): `2024年3月`
- `--era japanese`: `令和6年3月`

Ask whether this is a **targeted application** or a **master document**:
- **Master (default)**: no extra flags — produces a neutral reusable 履歴書.
- **Targeted**: `--target <company.json>` — tailors 志望動機 toward a specific employer.
  Create the target file before running:
  ```json
  {
    "company_name": "株式会社〇〇",
    "role_title": "iOSエンジニア",
    "company_summary": "...",
    "job_description_excerpt": "...",
    "emphasis_tags": ["mobile", "consumer"]
  }
  ```
  All fields are optional. See `TargetCompanyContext` in the repo for the full schema.

Key rules to follow when producing the rirekisho JSON in external mode:
- Current role: include the company entry with its actual start year/month. Then add a final continuation row with a **blank** date cell (`""`) and description `「現在に至る」`. Never put `「現在」` in the date column.
- Licenses/certifications: prefer standard Japanese names when one exists — e.g. `日本語能力試験N3 合格`, not `JLPT N3`.
- Naming: use Japanese legal entity names when commonly used in Japan; keep the choice consistent across all sections of the output.

### 6. Generate shokumukeirekisho (LLM — you drive)

```bash
jpresume generate shokumukeirekisho --workspace <ws> --external [options]
```

Output: `shokumukeirekisho.json` (職務経歴書 — detailed free-form work history with achievements, skills, and self-PR).

Ask user about:
- `--include-side-projects` — include personal/side projects section
- `--exclude-older-roles` — trim roles that are no longer relevant (typically 10+ years old, non-technical, or pre-pivot)
- `--era` — same as rirekisho
- `--target <company.json>` — tailored application mode (same JSON file as rirekisho; tailors 職務要約, 自己PR, role emphasis, achievement prioritization)

All flags fold into the content hash, so toggling them correctly re-generates.

Key rules to follow when producing the shokumukeirekisho JSON in external mode:
- **Skill taxonomy** — use these category names: `言語`, `フレームワーク`, `設計・開発`, `品質・改善`, `AI関連`, `その他`. Don't create generic `インフラ` or `ツール` buckets unless clearly the best fit.
- **Year counts** — prefer omitting exact year counts in prose unless the number materially strengthens the document. When used, prefer rounded phrasing like `10年以上` over a brittle exact count.
- **Metric phrasing** — rewrite quantified outcomes in natural Japanese business phrasing: `+29.8% incremental sign-ups` → `新規会員登録数の29.8%増加に寄与`.
- **Product vocabulary** — don't over-translate: product onboarding → `オンボーディング`, not `新人教育・導入支援`.
- **Naming** — same consistency rule as rirekisho: Japanese legal entity names when common; consistent across all sections.

### 7. Render + final review

```bash
jpresume render both --workspace <ws>
```

Writes `rirekisho.md`, `rirekisho.pdf`, `shokumukeirekisho.md`, `shokumukeirekisho.pdf`. The PDFs use Hiragino Sans for native Japanese typography (rirekisho is a grid drawn with CoreGraphics; shokumukeirekisho is free-form).

Show the user the output paths. If they want a quick text-only review, read `rirekisho.md` / `shokumukeirekisho.md`.

For refinements to Japanese phrasing (e.g., "make 自己PR less formal"), hand-edit `rirekisho.json` or `shokumukeirekisho.json` directly and re-run `render`.

## Iteration patterns

**"The self-PR is too formal"** → edit `rirekisho.json` → `jpresume render rirekisho --workspace <ws>`.

**"You got a date wrong"** → edit `normalized.json` → `jpresume repair --workspace <ws>` → `jpresume validate --workspace <ws>` → regenerate downstream with `jpresume generate <kind> --workspace <ws> --external` (the hash change forces regen).

**"Include my GitHub project as a side project"** → re-run `jpresume generate shokumukeirekisho --workspace <ws> --external --include-side-projects`, respond with updated JSON, `--ingest`, `render`.

**"Switch to reiwa dates everywhere"** → re-run both generate stages with `--era japanese`.

**"I'm applying to [Company X] for [role]"** → create a target context JSON file, then re-run both generate stages with `--target`:
```bash
# Create target file (any subset of fields is fine)
cat > target_companyX.json <<'EOF'
{
  "company_name": "株式会社〇〇",
  "role_title": "シニアiOSエンジニア",
  "company_summary": "消費者向けフィンテックアプリを運営",
  "emphasis_tags": ["consumer", "mobile", "growth"]
}
EOF

jpresume generate rirekisho --workspace <ws> --target target_companyX.json --external
# respond, ingest
jpresume generate shokumukeirekisho --workspace <ws> --target target_companyX.json --external
# respond, ingest
jpresume render both --workspace <ws>
```
Use a separate `--workspace` (e.g. `--workspace .jpresume-companyX`) to keep the targeted artifacts alongside the master set.

**"Completely redo the whole thing"** → `rm -rf <ws>/`, start at stage 1. Or use `--no-cache` on individual stages.

## Verifying the workspace at any point

```bash
jpresume inspect --workspace <ws>                   # overall status table
jpresume inspect <artifact> --workspace <ws>        # concise per-artifact summary
jpresume inspect <artifact> --workspace <ws> --json # raw artifact dump
```

`inspect` surfaces `ArtifactStatus` reasons like `stale — hash changed (a1b2… → 9f8e…)` and flags `role: "derived"` artifacts. If a stage shows `stale`, re-run it.

## Anti-patterns to avoid

- **Running `convert` when the user wants interactive review.** `convert` does the full pipeline internally with one provider call per LLM stage — no pauses. Use stepwise for review flows.
- **Editing `repaired.json` or `validation.json`.** They're `role: "derived"`. Edits are overwritten on next run. Edit `normalized.json` instead.
- **Skipping repair.** `generate` strictly requires `repaired.json`; it refuses to fall back to `normalized.json` to keep the review loop intact. If you see "run 'jpresume repair' first", run it.
- **Fabricating Japanese text.** Kanji for names, addresses, and furigana come from the config. If a field is missing from config, ask; don't invent.
- **Mixing ASCII names with kanji.** If config has `name_kanji` and `name_furigana`, use them consistently in all output.

## Resources

- [references/external-mode.md](references/external-mode.md) — prompt-bundle schema, response-file format, error recovery
- [references/config-schema.md](references/config-schema.md) — `jpresume_config.yaml` field reference and a draftable template
- [references/jpresume_config.example.yaml](references/jpresume_config.example.yaml) — a minimal, fictional config paired to the repo's `examples/resume.md`
- Repo examples (if present): `examples/resume.md` and rendered PDF outputs
- Repo docs: `CLAUDE.md`, `README.md`, `docs/plans/stepwise-agent-mode.md`
