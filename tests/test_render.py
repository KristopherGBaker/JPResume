"""Tests for template rendering."""

from jpresume.models import CompanyDetail, RirekishoData, ShokumukeirekishoData
from jpresume.render import render_rirekisho, render_shokumukeirekisho


def test_render_rirekisho():
    data = RirekishoData(
        creation_date="2026年4月16日",
        name_kanji="田中太郎",
        name_furigana="タナカタロウ",
        date_of_birth="1990年1月1日",
        postal_code="100-0001",
        address="東京都千代田区千代田1-1",
        phone="090-1234-5678",
        email="tanaka@example.com",
        education_history=[
            ("2010年4月", "東京大学 工学部 入学"),
            ("2014年3月", "東京大学 工学部 卒業"),
        ],
        work_history=[
            ("2014年4月", "株式会社ABC 入社"),
            ("", "現在に至る"),
        ],
        motivation="貴社の技術力に魅力を感じ、志望いたしました。",
        spouse=False,
        dependents=0,
    )

    md = render_rirekisho(data)

    assert "履歴書" in md
    assert "田中太郎" in md
    assert "タナカタロウ" in md
    assert "東京大学 工学部 入学" in md
    assert "株式会社ABC 入社" in md
    assert "現在に至る" in md
    assert "以上" in md
    assert "志望動機" in md
    assert "090-1234-5678" in md


def test_render_shokumukeirekisho():
    data = ShokumukeirekishoData(
        creation_date="2026年4月16日",
        name="田中太郎",
        career_summary="10年の経験を有するエンジニアです。",
        work_details=[
            CompanyDetail(
                company_name="株式会社ABC",
                period="2014年4月〜現在",
                industry="IT",
                role="シニアエンジニア",
                responsibilities=["システム設計", "チームリード"],
                achievements=["売上20%向上に貢献"],
            ),
        ],
        technical_skills={
            "言語": ["Python", "Go", "JavaScript"],
            "インフラ": ["AWS", "Docker"],
        },
        self_pr="技術力とリーダーシップを活かし貢献します。",
    )

    md = render_shokumukeirekisho(data)

    assert "職務経歴書" in md
    assert "職務要約" in md
    assert "株式会社ABC" in md
    assert "シニアエンジニア" in md
    assert "システム設計" in md
    assert "売上20%向上" in md
    assert "Python" in md
    assert "自己PR" in md
