# JPResume

Convert western-style resumes to Japanese format: 履歴書 (rirekisho) and 職務経歴書 (shokumukeirekisho).

## Install

Homebrew (recommended):
```bash
brew install KristopherGBaker/tap/jpresume
```

curl:
```bash
curl -L https://github.com/KristopherGBaker/JPResume/releases/latest/download/jpresume \
  -o /usr/local/bin/jpresume && chmod +x /usr/local/bin/jpresume
```

mise:
```bash
mise use -g ubi:KristopherGBaker/JPResume
```

Other options (Mint, build from source) → [docs/contributing.md](docs/contributing.md)

## Quick start

**Recommended: use the agent skill** with Claude Code, Cursor, Codex, or another AI coding assistant. The agent drives each stage interactively, acts as the LLM in external mode, and pauses for your review before generating output.

```bash
npx skills add KristopherGBaker/JPResume
```

Then ask your agent: *"Help me create a Japanese resume from my resume.md"*

**One-shot CLI:**

```bash
jpresume convert resume.md --provider anthropic --format both
```

Pass additional context (extra work/education history, style notes) inline or from a file:

```bash
jpresume convert resume.md --provider anthropic \
  --notes "Add my 2008-2010 contract role at PrototypeCo. Emphasize startup work."

jpresume convert resume.md --provider anthropic --notes notes/extras.md
```

The one-shot run includes a self-critique loop (deterministic constraint checks fed back to the LLM for repair) and a validation feedback loop on normalize, so it lands closer to the interactive agent flow than a single-call pipeline would.

## Features

- Parses markdown, DOCX, and PDF resumes
- Source-aware ingestion: markdown keeps a deterministic markdown parser, while DOCX/PDF/plain-text input is cleaned and normalized through a text-resume path
- LLM normalization — structured dates, bullet classification (achievement vs responsibility), skill grouping
- Validation — date ranges, overlapping roles, `is_current` consistency, total experience
- Self-critique loop — deterministic Japanese-output constraint checks (forbidden hype phrases, 「現在」 placement, duplicate sentences between 職務要約/自己PR, metric duplication) feed violations back to the LLM for repair, up to 3 passes per generate stage
- Validation feedback loop on normalize — re-prompts with validator output when fixable, up to 2 refinement passes with oscillation guard
- Interactive Japan-specific config — kanji name, furigana, education dates, work history, licenses — saved to YAML for reuse
- Tailored applications — `--target company.json` adjusts 志望動機, 職務要約, 自己PR, and role emphasis for a specific employer
- Free-form context — `--notes <path-or-text>` for extra work/education history or style preferences not in the resume or config
- Multi-provider AI — Anthropic, OpenAI, OpenRouter, Ollama (via [Shikisha](https://github.com/KristopherGBaker/Shikisha))
- Content-based caching — SHA-256 hash invalidation across all inputs (markdown, config, target, notes)
- PDF output — 履歴書 as a standard grid form (CoreGraphics + Hiragino Sans); 職務経歴書 as a free-form document
- Stepwise subcommands — pause, review, and hand-edit between any stage

## Documentation

| | |
|---|---|
| [CLI reference](docs/cli.md) | `convert` options, AI providers, pipeline, stepwise commands, workspace layout, external mode |
| [Agent skill](skills/japanese-resume/SKILL.md) | Full protocol for driving jpresume interactively with an AI agent |
| [Config reference](skills/japanese-resume/references/config-schema.md) | `jpresume_config.yaml` field reference and template |
| [External mode](skills/japanese-resume/references/external-mode.md) | Prompt bundle schema, response format, error recovery |
| [Contributing](docs/contributing.md) | Build, test, lint, release process |

## Notes

- PDF input is not treated as if it were markdown. Extracted PDF/OCR text is preprocessed, stored in the workspace, and passed to normalization alongside the advisory parsed resume.
- DOCX input follows the same source-aware text path as PDF/plain text: extract text first, then preprocess, parse, and normalize with the cleaned source text available to the LLM.
