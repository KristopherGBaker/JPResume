"""Config management: YAML persistence and interactive prompts."""

from __future__ import annotations

from datetime import date
from pathlib import Path

import yaml
from rich.console import Console
from rich.prompt import Confirm, Prompt

from jpresume.constants import PREFECTURES
from jpresume.models import (
    JapanConfig,
    JapaneseAddress,
    JapaneseEducationEntry,
    LicenseEntry,
    WesternResume,
)

console = Console()


def load_config(path: Path) -> JapanConfig | None:
    """Load config from YAML file, or return None if not found."""
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as f:
        data = yaml.safe_load(f)
    if not data:
        return None
    return JapanConfig.model_validate(data)


def save_config(config: JapanConfig, path: Path) -> None:
    """Save config to YAML file."""
    data = config.model_dump(mode="json", exclude_none=True)
    with open(path, "w", encoding="utf-8") as f:
        yaml.dump(data, f, allow_unicode=True, default_flow_style=False, sort_keys=False)
    console.print(f"  Config saved to [cyan]{path}[/cyan]")


def load_or_prompt_config(
    config_path: Path,
    western: WesternResume,
    force_reconfigure: bool = False,
) -> JapanConfig:
    """Load existing config or prompt user for Japan-specific information."""
    config = None
    if not force_reconfigure:
        config = load_config(config_path)

    if config:
        console.print(f"  Using saved config from [cyan]{config_path}[/cyan]")
        return config

    console.print("\n  No configuration found. Let's gather your Japan-specific information.")
    console.print("  This will be saved for future use.\n")

    config = _prompt_all(western)
    save_config(config, config_path)
    return config


COMPLETION_TYPES = {
    "1": ("卒業", "Graduated"),
    "2": ("中途退学", "Withdrew (中途退学)"),
    "3": ("中途退学（一身上の都合により）", "Withdrew - personal reasons"),
    "4": ("中途退学（経済的理由により）", "Withdrew - financial reasons"),
    "5": ("中途退学（家庭の事情により）", "Withdrew - family circumstances"),
}


def _prompt_one_education_entry(config: JapanConfig) -> None:
    """Prompt for a single education entry."""
    institution = Prompt.ask("    Institution name")
    institution_jp = Prompt.ask(
        "    Institution in Japanese (Enter to let AI translate)", default=""
    )
    degree = Prompt.ask("    Degree/Department (e.g. Computer Science)", default="")
    degree_jp = Prompt.ask(
        "    Degree in Japanese (e.g. コンピュータサイエンス学部)", default=""
    )
    start = Prompt.ask("    Start date (e.g. 2006年8月)")
    end = Prompt.ask("    End date (e.g. 2008年5月)")

    console.print("    Completion status:")
    for key, (_, label) in COMPLETION_TYPES.items():
        console.print(f"      {key}. {label}")
    status_choice = Prompt.ask("    Choose", choices=list(COMPLETION_TYPES.keys()), default="1")
    completion_jp = COMPLETION_TYPES[status_choice][0]

    inst_name = institution_jp or institution
    degree_name = degree_jp or degree
    label = f"{inst_name} {degree_name}".strip()

    config.education_japanese.append(
        JapaneseEducationEntry(year_month=start, description=f"{label} 入学")
    )
    config.education_japanese.append(
        JapaneseEducationEntry(year_month=end, description=f"{label} {completion_jp}")
    )


def _prompt_education_entries(config: JapanConfig, western: WesternResume) -> None:
    """Prompt for education entries found in the resume."""
    for edu in western.education:
        console.print(f"  [cyan]{edu.institution}[/cyan] — {edu.degree or 'N/A'}")
        start = Prompt.ask("    Start date (e.g. 2010年1月 or 2010年8月)")
        end = Prompt.ask("    End date (e.g. 2012年12月)")
        degree_jp = Prompt.ask(
            "    Degree in Japanese (e.g. コンピュータサイエンス学部)", default=""
        )
        institution_jp = Prompt.ask(
            "    Institution in Japanese (Enter to let AI translate)", default=""
        )

        console.print("    Completion status:")
        for key, (_, label) in COMPLETION_TYPES.items():
            console.print(f"      {key}. {label}")
        status_choice = Prompt.ask(
            "    Choose", choices=list(COMPLETION_TYPES.keys()), default="1"
        )
        completion_jp = COMPLETION_TYPES[status_choice][0]

        inst_name = institution_jp or edu.institution
        degree_name = degree_jp or edu.degree or ""
        label = f"{inst_name} {degree_name}".strip()

        config.education_japanese.append(
            JapaneseEducationEntry(year_month=start, description=f"{label} 入学")
        )
        config.education_japanese.append(
            JapaneseEducationEntry(year_month=end, description=f"{label} {completion_jp}")
        )


def _prompt_all(western: WesternResume) -> JapanConfig:
    """Run through all interactive prompts."""
    config = JapanConfig()

    # Personal Information
    console.print("[bold]── Personal Information ──[/bold]")
    config.name_kanji = Prompt.ask("  Full name in kanji")
    config.name_furigana = Prompt.ask("  Full name in furigana (katakana)")

    dob_str = Prompt.ask("  Date of birth (YYYY-MM-DD)")
    try:
        config.date_of_birth = date.fromisoformat(dob_str)
    except ValueError:
        console.print("  [yellow]Invalid date format, skipping.[/yellow]")

    config.gender = Prompt.ask("  Gender (optional, press Enter to skip)", default="")
    if not config.gender:
        config.gender = None

    # Address
    console.print("\n[bold]── Address ──[/bold]")
    addr = JapaneseAddress()
    addr.postal_code = Prompt.ask("  Postal code (〒XXX-XXXX)")

    console.print("  Prefectures: " + ", ".join(PREFECTURES[:5]) + "...")
    addr.prefecture = Prompt.ask("  Prefecture (都道府県)")
    addr.city = Prompt.ask("  City/Ward (市区町村)")
    addr.line1 = Prompt.ask("  Address line 1")
    addr.line2 = Prompt.ask("  Address line 2 (optional, Enter to skip)", default="")
    if not addr.line2:
        addr.line2 = None
    addr.furigana = Prompt.ask("  Address furigana")
    config.address_current = addr

    has_contact_addr = Confirm.ask("  Different contact address?", default=False)
    if has_contact_addr:
        console.print("\n[bold]── Contact Address ──[/bold]")
        caddr = JapaneseAddress()
        caddr.postal_code = Prompt.ask("  Contact postal code")
        caddr.prefecture = Prompt.ask("  Contact prefecture")
        caddr.city = Prompt.ask("  Contact city")
        caddr.line1 = Prompt.ask("  Contact address line 1")
        caddr.line2 = Prompt.ask("  Contact address line 2 (optional)", default="")
        if not caddr.line2:
            caddr.line2 = None
        caddr.furigana = Prompt.ask("  Contact address furigana")
        config.address_contact = caddr

    # Contact
    console.print("\n[bold]── Contact ──[/bold]")
    default_phone = western.contact.phone or ""
    config.phone = Prompt.ask("  Phone number", default=default_phone)

    default_email = western.contact.email or ""
    config.email = Prompt.ask("  Email", default=default_email)

    # Photo
    photo = Prompt.ask("  Photo path (optional, Enter to skip)", default="")
    config.photo_path = photo if photo else None

    # Additional
    console.print("\n[bold]── Additional ──[/bold]")
    commute = Prompt.ask("  Commute time (e.g. 約45分, Enter to skip)", default="")
    config.commute_time = commute if commute else None

    spouse = Prompt.ask("  Spouse? (yes/no, Enter to skip)", default="")
    if spouse.lower() in ("yes", "y"):
        config.spouse = True
    elif spouse.lower() in ("no", "n"):
        config.spouse = False

    deps = Prompt.ask("  Number of dependents (Enter to skip)", default="")
    if deps.isdigit():
        config.dependents = int(deps)

    deps_excl = Prompt.ask("  Dependents excluding spouse (Enter to skip)", default="")
    if deps_excl.isdigit():
        config.dependents_excl_spouse = int(deps_excl)

    # Education history
    console.print("\n[bold]── Education History ──[/bold]")
    if western.education:
        console.print("  From your resume:")
        for edu in western.education:
            dates = f" ({edu.graduation_date})" if edu.graduation_date else ""
            console.print(f"    - {edu.institution} — {edu.degree or 'N/A'}{dates}")
    console.print("  Please provide details for each education entry.")
    console.print("  Include any education not on your resume (e.g. earlier schools).")
    console.print("  Entries will appear in chronological order on the 履歴書.\n")

    _prompt_education_entries(config, western)

    # Additional education not on resume
    add_more = Confirm.ask("\n  Add more education entries not on your resume?", default=False)
    while add_more:
        _prompt_one_education_entry(config)
        add_more = Confirm.ask("  Add another?", default=False)

    # Sort education entries chronologically
    config.education_japanese.sort(key=lambda e: e.year_month)

    # Work history dates (confirm/correct dates from resume)
    console.print("\n[bold]── Work History Dates ──[/bold]")
    if western.experience:
        console.print("  Confirm or correct dates for each position.")
        for exp in western.experience:
            if not exp.start_date and not exp.title:
                continue  # Skip entries like "Projects" with no dates
            dates_str = f"{exp.start_date or '?'} – {exp.end_date or '?'}"
            console.print(f"\n  [cyan]{exp.company}[/cyan] ({exp.title or 'N/A'}) — {dates_str}")
            correct = Confirm.ask("    Dates correct?", default=True)
            if not correct:
                start = Prompt.ask("    Start date (e.g. 2020年1月)")
                end = Prompt.ask("    End date (e.g. 2023年5月, or 現在)")
                config.work_japanese.append(
                    JapaneseEducationEntry(year_month=start, description=f"{exp.company} 入社")
                )
                if end.lower() not in ("現在", "present", "current"):
                    config.work_japanese.append(
                        JapaneseEducationEntry(
                            year_month=end, description="一身上の都合により退職"
                        )
                    )

    # Licenses
    console.print("\n[bold]── Licenses & Certifications ──[/bold]")
    if western.certifications:
        console.print("  From your resume:")
        for cert in western.certifications:
            console.print(f"    - {cert}")
    console.print("  Add Japanese licenses/certifications (blank line to finish):")
    while True:
        name = Prompt.ask("    License name (Enter to finish)", default="")
        if not name:
            break
        ym = Prompt.ask("    Year/Month (e.g. 2022年3月)")
        config.licenses.append(LicenseEntry(year_month=ym, name=name))

    # Motivation & PR
    console.print("\n[bold]── Motivation & PR ──[/bold]")
    motivation = Prompt.ask("  志望動機 (motivation, Enter to auto-generate)", default="")
    config.motivation = motivation if motivation else None

    self_pr = Prompt.ask("  自己PR (self-promotion, Enter to auto-generate)", default="")
    config.self_pr = self_pr if self_pr else None

    hobbies = Prompt.ask("  趣味・特技 (hobbies/skills, Enter to skip)", default="")
    config.hobbies = hobbies if hobbies else None

    return config
