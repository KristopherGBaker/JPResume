"""Render Japanese resume data to markdown using Jinja2 templates."""

from __future__ import annotations

from pathlib import Path

from jinja2 import Environment, FileSystemLoader

from jpresume.models import RirekishoData, ShokumukeirekishoData

TEMPLATES_DIR = Path(__file__).parent / "templates"


def _get_env() -> Environment:
    return Environment(
        loader=FileSystemLoader(str(TEMPLATES_DIR)),
        keep_trailing_newline=True,
        trim_blocks=True,
        lstrip_blocks=True,
    )


def render_rirekisho(data: RirekishoData) -> str:
    """Render rirekisho data to markdown."""
    env = _get_env()
    template = env.get_template("rirekisho.md.jinja2")
    return template.render(**data.model_dump())


def render_shokumukeirekisho(data: ShokumukeirekishoData) -> str:
    """Render shokumukeirekisho data to markdown."""
    env = _get_env()
    template = env.get_template("shokumukeirekisho.md.jinja2")
    # Convert CompanyDetail models to dicts for template
    dump = data.model_dump()
    return template.render(**dump)
