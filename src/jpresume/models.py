"""Data models for western and Japanese resume formats."""

from __future__ import annotations

from datetime import date
from typing import Any

from pydantic import BaseModel, Field


# --- Western Resume (parsed from input markdown) ---


class ContactInfo(BaseModel):
    email: str | None = None
    phone: str | None = None
    address: str | None = None
    linkedin: str | None = None
    github: str | None = None
    website: str | None = None


class WorkEntry(BaseModel):
    company: str
    title: str | None = None
    start_date: str | None = None
    end_date: str | None = None
    location: str | None = None
    bullets: list[str] = Field(default_factory=list)


class EducationEntry(BaseModel):
    institution: str
    degree: str | None = None
    field: str | None = None
    graduation_date: str | None = None
    gpa: str | None = None


class WesternResume(BaseModel):
    name: str | None = None
    contact: ContactInfo = Field(default_factory=ContactInfo)
    summary: str | None = None
    experience: list[WorkEntry] = Field(default_factory=list)
    education: list[EducationEntry] = Field(default_factory=list)
    skills: list[str] = Field(default_factory=list)
    certifications: list[str] = Field(default_factory=list)
    languages: list[str] = Field(default_factory=list)
    raw_sections: dict[str, str] = Field(default_factory=dict)


# --- Japan-specific config (interactive + YAML) ---


class JapaneseAddress(BaseModel):
    postal_code: str | None = None
    prefecture: str | None = None
    city: str | None = None
    line1: str | None = None
    line2: str | None = None
    furigana: str | None = None


class JapaneseEducationEntry(BaseModel):
    year_month: str
    description: str


class LicenseEntry(BaseModel):
    year_month: str
    name: str


class JapanConfig(BaseModel):
    name_kanji: str | None = None
    name_furigana: str | None = None
    date_of_birth: date | None = None
    gender: str | None = None
    address_current: JapaneseAddress = Field(default_factory=JapaneseAddress)
    address_contact: JapaneseAddress | None = None
    phone: str | None = None
    email: str | None = None
    photo_path: str | None = None
    commute_time: str | None = None
    spouse: bool | None = None
    dependents: int | None = None
    dependents_excl_spouse: int | None = None
    motivation: str | None = None
    hobbies: str | None = None
    self_pr: str | None = None
    education_japanese: list[JapaneseEducationEntry] = Field(default_factory=list)
    work_japanese: list[JapaneseEducationEntry] = Field(default_factory=list)
    licenses: list[LicenseEntry] = Field(default_factory=list)


# --- Output models (assembled for rendering) ---


class RirekishoData(BaseModel):
    """Data for rendering a 履歴書."""

    creation_date: str
    name_kanji: str
    name_furigana: str
    date_of_birth: str
    gender: str | None = None
    postal_code: str | None = None
    address: str | None = None
    address_furigana: str | None = None
    contact_postal_code: str | None = None
    contact_address: str | None = None
    contact_address_furigana: str | None = None
    phone: str | None = None
    email: str | None = None
    photo_path: str | None = None
    education_history: list[tuple[str, str]] = Field(default_factory=list)
    work_history: list[tuple[str, str]] = Field(default_factory=list)
    licenses: list[tuple[str, str]] = Field(default_factory=list)
    motivation: str | None = None
    hobbies: str | None = None
    commute_time: str | None = None
    spouse: bool | None = None
    dependents: int | None = None
    dependents_excl_spouse: int | None = None


class CompanyDetail(BaseModel):
    """Detailed work history for one company in 職務経歴書."""

    company_name: str
    period: str
    industry: str | None = None
    company_size: str | None = None
    employment_type: str | None = None
    role: str | None = None
    department: str | None = None
    responsibilities: list[str] = Field(default_factory=list)
    achievements: list[str] = Field(default_factory=list)


class ShokumukeirekishoData(BaseModel):
    """Data for rendering a 職務経歴書."""

    creation_date: str
    name: str
    career_summary: str
    work_details: list[CompanyDetail] = Field(default_factory=list)
    technical_skills: dict[str, list[str]] = Field(default_factory=dict)
    self_pr: str | None = None


# --- AI response models ---


class GapAnalysis(BaseModel):
    """Response from AI gap analysis call."""

    present_fields: list[str] = Field(default_factory=list)
    missing_fields: list[str] = Field(default_factory=list)
    suggestions: dict[str, Any] = Field(default_factory=dict)
