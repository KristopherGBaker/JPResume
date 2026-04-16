"""Tests for data models."""

from datetime import date

from jpresume.models import (
    CompanyDetail,
    JapanConfig,
    RirekishoData,
    ShokumukeirekishoData,
    WesternResume,
)


def test_western_resume_defaults():
    r = WesternResume()
    assert r.name is None
    assert r.experience == []
    assert r.skills == []


def test_japan_config_from_yaml(sample_config_data):
    config = JapanConfig.model_validate(sample_config_data)
    assert config.name_kanji == "ドウ ジェーン"
    assert config.date_of_birth == date(1993, 5, 15)
    assert config.address_current.prefecture == "東京都"
    assert config.spouse is False


def test_japan_config_roundtrip():
    config = JapanConfig(
        name_kanji="田中太郎",
        name_furigana="タナカタロウ",
        date_of_birth=date(1990, 1, 1),
    )
    data = config.model_dump(mode="json")
    restored = JapanConfig.model_validate(data)
    assert restored.name_kanji == "田中太郎"
    assert restored.date_of_birth == date(1990, 1, 1)


def test_rirekisho_data():
    data = RirekishoData(
        creation_date="2026年4月16日",
        name_kanji="田中太郎",
        name_furigana="タナカタロウ",
        date_of_birth="1990年1月1日",
        education_history=[("2010年4月", "東京大学 入学")],
        work_history=[("2014年4月", "株式会社ABC 入社")],
    )
    assert len(data.education_history) == 1
    assert data.work_history[0][1] == "株式会社ABC 入社"


def test_shokumukeirekisho_data():
    data = ShokumukeirekishoData(
        creation_date="2026年4月16日",
        name="田中太郎",
        career_summary="テスト",
        work_details=[
            CompanyDetail(
                company_name="ABC Corp",
                period="2020年〜現在",
                responsibilities=["開発"],
                achievements=["売上向上"],
            )
        ],
        technical_skills={"言語": ["Python", "Go"]},
    )
    assert len(data.work_details) == 1
    assert "Python" in data.technical_skills["言語"]
