"""AI integration for resume translation and adaptation.

Supports multiple providers: Anthropic, OpenAI, OpenRouter, Ollama.
"""

from __future__ import annotations

import json
import os
from abc import ABC, abstractmethod
from datetime import date
from typing import Any

from rich.console import Console

from jpresume.models import (
    CompanyDetail,
    JapanConfig,
    RirekishoData,
    ShokumukeirekishoData,
    WesternResume,
)

console = Console()


# --- Provider abstraction ---


class AIProvider(ABC):
    """Abstract base for LLM providers."""

    @abstractmethod
    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        """Send a chat message and return the assistant response text."""
        ...

    @property
    @abstractmethod
    def name(self) -> str:
        ...


class AnthropicProvider(AIProvider):
    def __init__(self, model: str):
        import anthropic

        api_key = os.environ.get("ANTHROPIC_API_KEY")
        if not api_key:
            raise EnvironmentError(
                "ANTHROPIC_API_KEY environment variable is required for Anthropic provider"
            )
        self.client = anthropic.Anthropic(api_key=api_key)
        self.model = model

    @property
    def name(self) -> str:
        return f"Anthropic ({self.model})"

    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        response = self.client.messages.create(
            model=self.model,
            max_tokens=4096,
            temperature=temperature,
            system=[{"type": "text", "text": system, "cache_control": {"type": "ephemeral"}}],
            messages=[{"role": "user", "content": user}],
        )
        return response.content[0].text


class OpenAIProvider(AIProvider):
    """OpenAI-compatible provider (works with OpenAI API directly)."""

    def __init__(self, model: str, base_url: str | None = None, api_key_env: str = "OPENAI_API_KEY"):
        from openai import OpenAI

        api_key = os.environ.get(api_key_env)
        if not api_key:
            raise EnvironmentError(
                f"{api_key_env} environment variable is required for OpenAI provider"
            )
        kwargs: dict[str, Any] = {"api_key": api_key}
        if base_url:
            kwargs["base_url"] = base_url
        self.client = OpenAI(**kwargs)
        self.model = model
        self._name = "OpenAI"

    @property
    def name(self) -> str:
        return f"{self._name} ({self.model})"

    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        response = self.client.chat.completions.create(
            model=self.model,
            temperature=temperature,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )
        return response.choices[0].message.content or ""


class OpenRouterProvider(OpenAIProvider):
    """OpenRouter provider (OpenAI-compatible API)."""

    def __init__(self, model: str):
        super().__init__(
            model=model,
            base_url="https://openrouter.ai/api/v1",
            api_key_env="OPENROUTER_API_KEY",
        )
        self._name = "OpenRouter"


class OllamaProvider(AIProvider):
    """Ollama local provider (OpenAI-compatible API)."""

    def __init__(self, model: str, base_url: str = "http://localhost:11434/v1"):
        from openai import OpenAI

        self.client = OpenAI(api_key="ollama", base_url=base_url)
        self.model = model

    @property
    def name(self) -> str:
        return f"Ollama ({self.model})"

    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        response = self.client.chat.completions.create(
            model=self.model,
            temperature=temperature,
            messages=[
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
        )
        return response.choices[0].message.content or ""


class ClaudeCLIProvider(AIProvider):
    """Claude Code CLI provider (claude -p)."""

    def __init__(self, model: str = ""):
        self.model = model

    @property
    def name(self) -> str:
        return "Claude CLI"

    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        import subprocess

        prompt = f"{system}\n\n{user}"
        cmd = ["claude", "-p", prompt]
        if self.model:
            cmd.extend(["--model", self.model])

        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=120,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"Claude CLI failed (exit {result.returncode}): "
                f"{result.stderr or result.stdout}"
            )
        return result.stdout.strip()


class CodexCLIProvider(AIProvider):
    """Codex CLI provider (codex exec)."""

    def __init__(self, model: str = ""):
        self.model = model

    @property
    def name(self) -> str:
        return "Codex CLI"

    def chat(self, system: str, user: str, *, temperature: float = 0.3) -> str:
        import subprocess

        prompt = f"{system}\n\n{user}"
        cmd = ["codex", "exec", "--skip-git-repo-check", prompt]
        if self.model:
            cmd.extend(["--model", self.model])

        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=120,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"Codex CLI failed (exit {result.returncode}): "
                f"{result.stderr or result.stdout}"
            )
        return result.stdout.strip()


PROVIDERS = {
    "anthropic": AnthropicProvider,
    "openai": OpenAIProvider,
    "openrouter": OpenRouterProvider,
    "ollama": OllamaProvider,
    "claude-cli": ClaudeCLIProvider,
    "codex-cli": CodexCLIProvider,
}

DEFAULT_MODELS = {
    "anthropic": "claude-sonnet-4-6",
    "openai": "gpt-5.4",
    "openrouter": "gemma4",
    "ollama": "gemma4",
    "claude-cli": "",
    "codex-cli": "",
}


def create_provider(provider_name: str, model: str | None = None) -> AIProvider:
    """Create an AI provider by name.

    Args:
        provider_name: One of "anthropic", "openai", "openrouter", "ollama"
        model: Model name override. If None, uses provider default.
    """
    provider_name = provider_name.lower()
    if provider_name not in PROVIDERS:
        raise ValueError(
            f"Unknown provider '{provider_name}'. Choose from: {', '.join(PROVIDERS)}"
        )
    model = model or DEFAULT_MODELS[provider_name]
    return PROVIDERS[provider_name](model)


# --- System prompts ---


RIREKISHO_SYSTEM = """\
You are an expert in Japanese resume (履歴書) formatting. You will receive:
1. A parsed western-style resume (JSON)
2. Japan-specific configuration data (JSON)

Your task is to produce a complete 履歴書 data structure in JSON format.

Rules:
- NEVER fabricate or guess dates, company details, or any factual information. Only use data explicitly provided in the input. If a date is missing, omit that entry or use the placeholder "年月不明" and flag it.
- Convert all provided dates to {era_style} format (e.g., {era_example})
- Education entries should follow Japanese convention:
  - Entry: "〇〇大学 〇〇学部 入学" / Graduation: "〇〇大学 〇〇学部 卒業"
  - For high school equivalent, use appropriate Japanese terms
  - Use education dates from japan_config.education_japanese if provided, otherwise from the western resume
- Work entries should follow Japanese convention:
  - Entry: "株式会社〇〇 入社" / Departure: "一身上の都合により退職" (or "会社都合により退職")
  - Current position: "株式会社〇〇 入社" with "現在に至る" as the final entry
  - Use work dates from japan_config.work_japanese if provided, otherwise from the western resume
- If 志望動機 (motivation) is not provided, generate an appropriate one based on the person's background
- If 趣味・特技 (hobbies) is not provided, suggest appropriate ones based on the resume
- All text output must be in Japanese

Return ONLY valid JSON matching this structure:
{{
  "creation_date": "string (today's date in Japanese format)",
  "name_kanji": "string",
  "name_furigana": "string",
  "date_of_birth": "string (Japanese format)",
  "gender": "string or null",
  "postal_code": "string or null",
  "address": "string or null",
  "address_furigana": "string or null",
  "phone": "string or null",
  "email": "string or null",
  "education_history": [["year_month", "description"], ...],
  "work_history": [["year_month", "description"], ...],
  "licenses": [["year_month", "description"], ...],
  "motivation": "string",
  "hobbies": "string or null",
  "commute_time": "string or null",
  "spouse": true/false/null,
  "dependents": 0,
  "dependents_excl_spouse": 0
}}
"""

SHOKUMUKEIREKISHO_SYSTEM = """\
You are an expert in Japanese career history documents (職務経歴書). You will receive:
1. A parsed western-style resume (JSON)
2. Japan-specific configuration data (JSON)

Your task is to produce a complete 職務経歴書 data structure in JSON format.

Rules:
- NEVER fabricate or guess dates, company details, or any factual information. Only use data explicitly provided in the input.
- Write a concise 職務要約 (career summary) of 3-4 sentences in formal Japanese
- For each work experience, create a detailed entry in formal Japanese business language:
  - Translate and expand bullet points into natural Japanese descriptions
  - Include role, department, responsibilities, and achievements
  - Use appropriate Japanese business terminology
  - Use work dates from japan_config.work_japanese if provided, otherwise from the western resume
- Categorize technical skills into groups (言語, フレームワーク, インフラ, データベース, ツール, etc.)
- If 自己PR is not provided, generate one highlighting the person's key strengths
- All dates should be in {era_style} format
- All text output must be in Japanese

Return ONLY valid JSON matching this structure:
{{
  "creation_date": "string",
  "name": "string",
  "career_summary": "string",
  "work_details": [
    {{
      "company_name": "string",
      "period": "string",
      "industry": "string or null",
      "company_size": "string or null",
      "employment_type": "正社員/契約社員/etc or null",
      "role": "string or null",
      "department": "string or null",
      "responsibilities": ["string", ...],
      "achievements": ["string", ...]
    }}
  ],
  "technical_skills": {{
    "category_name": ["skill1", "skill2", ...]
  }},
  "self_pr": "string"
}}
"""


# --- Main AI class ---


class ResumeAI:
    """Orchestrates AI calls for resume conversion."""

    def __init__(
        self,
        provider: str = "anthropic",
        model: str | None = None,
        verbose: bool = False,
    ):
        self.provider = create_provider(provider, model)
        self.verbose = verbose
        console.print(f"  Using AI provider: [cyan]{self.provider.name}[/cyan]")

    def _call(self, system: str, user: str) -> str:
        """Make an AI call with logging."""
        if self.verbose:
            console.print(f"\n[dim]System prompt ({len(system)} chars):[/dim]")
            console.print(f"[dim]{system[:200]}...[/dim]")
            console.print(f"\n[dim]User message ({len(user)} chars):[/dim]")
            console.print(f"[dim]{user[:200]}...[/dim]")

        response = self.provider.chat(system, user)

        if self.verbose:
            console.print(f"\n[dim]Response ({len(response)} chars):[/dim]")
            console.print(f"[dim]{response[:500]}...[/dim]")

        return response

    def _parse_json(self, text: str) -> dict:
        """Extract and parse JSON from AI response."""
        text = text.strip()

        # Strip markdown code fences if present
        if "```" in text:
            # Extract content between first ``` and last ```
            parts = text.split("```")
            for part in parts[1:]:
                # Skip the language identifier line (e.g. "json\n")
                content = part.strip()
                if content.startswith(("json", "JSON")):
                    content = content.split("\n", 1)[1] if "\n" in content else ""
                content = content.strip()
                if content.startswith("{"):
                    try:
                        return json.loads(content)
                    except json.JSONDecodeError:
                        pass

        # Try direct parse
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            pass

        # Extract first JSON object from text (handles trailing explanation text)
        brace_depth = 0
        start = text.index("{")
        for i, ch in enumerate(text[start:], start):
            if ch == "{":
                brace_depth += 1
            elif ch == "}":
                brace_depth -= 1
                if brace_depth == 0:
                    return json.loads(text[start : i + 1])

        raise ValueError(f"Could not extract valid JSON from AI response:\n{text[:500]}")

    def generate_rirekisho(
        self, western: WesternResume, config: JapanConfig, *, era: str = "western"
    ) -> RirekishoData:
        """Generate rirekisho data using AI."""
        if era == "japanese":
            era_style = "Japanese era (令和/平成)"
            era_example = "令和2年4月"
        else:
            era_style = "western year"
            era_example = "2020年4月"

        system = RIREKISHO_SYSTEM.format(era_style=era_style, era_example=era_example)
        user = json.dumps(
            {
                "western_resume": western.model_dump(mode="json"),
                "japan_config": config.model_dump(mode="json", exclude_none=True),
                "today": date.today().isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        )

        response = self._call(system, user)
        data = self._parse_json(response)
        return RirekishoData.model_validate(data)

    def generate_shokumukeirekisho(
        self, western: WesternResume, config: JapanConfig, *, era: str = "western"
    ) -> ShokumukeirekishoData:
        """Generate shokumukeirekisho data using AI."""
        if era == "japanese":
            era_style = "Japanese era (令和/平成)"
        else:
            era_style = "western year"

        system = SHOKUMUKEIREKISHO_SYSTEM.format(era_style=era_style)
        user = json.dumps(
            {
                "western_resume": western.model_dump(mode="json"),
                "japan_config": config.model_dump(mode="json", exclude_none=True),
                "today": date.today().isoformat(),
            },
            ensure_ascii=False,
            indent=2,
        )

        response = self._call(system, user)
        data = self._parse_json(response)
        return ShokumukeirekishoData.model_validate(data)
