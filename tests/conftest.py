"""Shared test fixtures."""

from pathlib import Path

import pytest

FIXTURES_DIR = Path(__file__).parent / "fixtures"


@pytest.fixture
def sample_resume_text():
    return (FIXTURES_DIR / "sample_resume.md").read_text()


@pytest.fixture
def sample_config_data():
    import yaml
    return yaml.safe_load((FIXTURES_DIR / "sample_config.yaml").read_text())
