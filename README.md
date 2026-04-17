# JPResume

Convert western-style resumes to Japanese format: 履歴書 (rirekisho) and 職務経歴書 (shokumukeirekisho).

## Install

Homebrew (recommended):
```bash
brew tap KristopherGBaker/tap && brew install jpresume
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
jpresume convert resume.md --provider claude-cli --format both
```

## Features

- Parses markdown and PDF resumes (text-layer extraction; Vision OCR fallback for scanned PDFs)
- LLM normalization — structured dates, bullet classification (achievement vs responsibility), skill grouping
- Validation — date ranges, overlapping roles, `is_current` consistency, total experience
- Interactive Japan-specific config — kanji name, furigana, education dates, work history, licenses — saved to YAML for reuse
- Tailored applications — `--target company.json` adjusts 志望動機, 職務要約, 自己PR, and role emphasis for a specific employer
- Multi-provider AI — Anthropic, OpenAI, OpenRouter, Ollama, Claude CLI, Codex CLI
- Content-based caching — SHA-256 hash invalidation across all inputs
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
