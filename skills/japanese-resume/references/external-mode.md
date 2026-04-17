# External-mode reference

Detailed protocol for driving `jpresume`'s LLM stages (`normalize`, `generate rirekisho`, `generate shokumukeirekisho`) in `--external` mode.

## Prompt bundle schema

When you run `jpresume <stage> --workspace <ws> --external`, the CLI writes `<ws>/<stage>.prompt.json`:

```json
{
  "stage": "normalize",
  "artifact_kind": "normalized",
  "workspace": "/abs/path/.jpresume",
  "source_artifacts": ["parsed.json", "inputs.json"],
  "stage_options": {
    "include_side_projects": "false",
    "exclude_older_roles": "false",
    "era": "western"
  },
  "system": "You are a resume normalizer. …",
  "user": "{\n  \"western_resume\": {...},\n  \"japan_config\": {...}\n}",
  "temperature": 0.2,
  "expected_output_format": "json-only",
  "response_schema": {},
  "response_path": "/abs/path/.jpresume/normalize.response.json"
}
```

| Field | Meaning |
|-------|---------|
| `stage` | `normalize` / `rirekisho` / `shokumukeirekisho` |
| `artifact_kind` | The output kind the ingest step will write |
| `source_artifacts` | Which workspace files the bundle derives from — for audit/debug |
| `stage_options` | Flags that influenced the prompt (era, side-projects, etc.). Reproduce these if the user asks you to re-generate matching a prior run. |
| `system` | The full system prompt. Contains the schema description, hard rules (no fabrication, date format, required fields), and output contract. **Read this carefully.** |
| `user` | The JSON payload to operate on. For `normalize` it's `{western_resume, japan_config}`. For the generate stages it's `{normalized_resume, japan_config, options}`. |
| `temperature` | Advisory; you don't need to honor it numerically. `0.2` signals "stick close to inputs, minimal creativity." |
| `expected_output_format` | Always `json-only` for MVP. |
| `response_schema` | Empty map for MVP — schema is prose-only inside `system`. |
| `response_path` | Where to write your reply. Always `<ws>/<stage>.response.json`. |

## Producing the response

1. Read `<ws>/<stage>.prompt.json`.
2. Think through the `system` requirements: required fields, schema shape, classification rules, date format, what to do when data is ambiguous.
3. Operate on the `user` payload to produce the output JSON.
4. Write the JSON **body only** to `response_path` using the `Write` tool:

```json
{
  "name": "…",
  "experiences": [
    {
      "company": "…",
      "title": "…",
      "start_date": {"year": 2020, "month": 1},
      "end_date": null,
      "is_current": true,
      "bullets": [
        {"text": "…", "type": "achievement", "confidence": "high"}
      ]
    }
  ]
}
```

The CLI's `JSONExtractor` is forgiving — it strips code fences and does brace-matching — but plain JSON is safest.

5. Run `jpresume <stage> --workspace <ws> --ingest`.

## Error recovery

If `--ingest` fails, the CLI writes `<ws>/<stage>.error.json`:

```json
{
  "stage": "normalize",
  "error": "keyNotFound(CodingKeys(stringValue: \"confidence\", intValue: nil)) …",
  "response_path": "/abs/path/.jpresume/normalize.response.json",
  "timestamp": "2026-04-17T12:00:00Z"
}
```

Recovery:

1. Read the error file — the decoder path tells you which field is broken.
2. Read your response file and fix the issue (missing field, wrong type, bad enum value).
3. Write the corrected JSON back to `response_path`.
4. Re-run `--ingest`.

Common decoder errors:

| Error pattern | Cause | Fix |
|---------------|-------|-----|
| `keyNotFound(… "confidence")` | Bullet or entry missing `confidence` | Add `"confidence": "high"` or `"low"` |
| `typeMismatch` on `start_date` | You wrote a string instead of `{year, month}` | Use `{"year": 2020, "month": 1}` |
| `valueNotFound` on `end_date` | `null` required but missing | For current roles, set `"end_date": null, "is_current": true` |
| `dataCorrupted` with "Expected to decode …" | Wrong enum value | Check `system` for allowed values (e.g. `achievement` / `responsibility`, not `accomplishment`) |

## Rules to carry across every LLM stage

- **No fabrication.** If the user didn't provide a date, don't invent one. Mark `confidence: "low"` instead.
- **Preserve specificity.** Don't generalize "Led 5-engineer team" to "Led team." The generate stages translate — they don't summarize.
- **Translate content, not structure.** Keep section ordering consistent with Japanese conventions (education chronological ascending for rirekisho, work history descending for shokumukeirekisho).
- **Names and addresses come from `japan_config`.** The `user` payload includes both the western resume and the config — cross-reference. If config has `name_kanji`, use it, don't transliterate from the English.

## Internal mode fallback

If external mode is failing repeatedly (e.g. stuck on some schema detail), you can fall back to internal mode for that one stage:

```bash
jpresume <stage> --workspace <ws> --provider claude-cli
```

This shells out to `claude -p` with the same prompts. Useful as an escape hatch but loses the interactive review benefit.
