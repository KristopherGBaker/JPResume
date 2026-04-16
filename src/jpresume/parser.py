"""Parse western-style markdown resumes into structured data."""

from __future__ import annotations

import re

import mistune

from jpresume.constants import SECTION_PATTERNS
from jpresume.models import ContactInfo, EducationEntry, WesternResume, WorkEntry


def parse_resume(text: str) -> WesternResume:
    """Parse a markdown resume into a WesternResume model."""
    sections = _split_sections(text)
    resume = WesternResume()

    # Try to extract name from the first H1
    resume.name = _extract_name(text)

    # Extract contact info from header area (before first section)
    header = sections.pop("_header", "")
    resume.contact = _extract_contact(header)

    for heading, content in sections.items():
        category = _classify_section(heading)

        if category == "summary":
            resume.summary = content.strip()
        elif category == "experience":
            resume.experience = _parse_experience(content)
        elif category == "education":
            resume.education = _parse_education(content)
        elif category == "skills":
            resume.skills = _parse_skills(content)
        elif category == "certifications":
            resume.certifications = _parse_list_items(content)
        elif category == "languages":
            resume.languages = _parse_list_items(content)
        else:
            resume.raw_sections[heading] = content.strip()

    return resume


def _extract_name(text: str) -> str | None:
    """Extract name from the first H1 heading or first bold line."""
    # Try H1 first
    match = re.search(r"^#\s+(.+)$", text, re.MULTILINE)
    if match:
        return match.group(1).strip()
    # Try standalone bold line (e.g. **KRISTOPHER BAKER**)
    match = re.search(r"^\*\*([^*]+)\*\*\s*$", text, re.MULTILINE)
    if match:
        return match.group(1).strip()
    return None


def _split_sections(text: str) -> dict[str, str]:
    """Split markdown into sections by headings.

    Supports H2 (## Heading), H1 (# Heading), and standalone bold lines
    (**HEADING**) as section delimiters.

    Returns a dict of heading -> content. Content before the first section
    is stored under "_header".
    """
    sections: dict[str, str] = {}

    # Try H2 headings first
    pattern = re.compile(r"^##\s+(.+)$", re.MULTILINE)
    matches = list(pattern.finditer(text))

    if not matches:
        # Try H1 headings (skip first which is usually name)
        pattern = re.compile(r"^#\s+(.+)$", re.MULTILINE)
        matches = list(pattern.finditer(text))
        if len(matches) > 1:
            sections["_header"] = text[: matches[1].start()]
            for i, m in enumerate(matches[1:]):
                idx = i + 1
                end = matches[idx + 1].start() if idx + 1 < len(matches) else len(text)
                sections[m.group(1).strip()] = text[m.end() : end]
            return sections

    if not matches:
        # Try standalone bold lines as section headings
        # Match lines that are ONLY a bold word/phrase (no pipes, no other text)
        # This avoids matching "**Company** | Title" experience lines
        pattern = re.compile(r"^(\*\*[A-Z][A-Z &]+\*\*)\s*$", re.MULTILINE)
        matches = list(pattern.finditer(text))

        if matches:
            # First bold line is likely the name
            sections["_header"] = text[: matches[0].end()]
            # Find section-level bold headings (skip first = name)
            section_matches = []
            for m in matches:
                heading = m.group(1).strip("* ")
                if _classify_section(heading) is not None:
                    section_matches.append(m)

            if not section_matches:
                # Treat all bold lines after first as sections
                section_matches = matches[1:]

            for i, m in enumerate(section_matches):
                heading = m.group(1).strip("* ")
                start = m.end()
                end = section_matches[i + 1].start() if i + 1 < len(section_matches) else len(text)
                sections[heading] = text[start:end]
            return sections

        sections["_header"] = text
        return sections

    # Standard H2 heading split
    sections["_header"] = text[: matches[0].start()]
    for i, match in enumerate(matches):
        heading = match.group(1).strip()
        start = match.end()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        sections[heading] = text[start:end]

    return sections


def _classify_section(heading: str) -> str | None:
    """Classify a section heading into a known category."""
    heading_lower = heading.lower().strip()
    for category, patterns in SECTION_PATTERNS.items():
        for pattern in patterns:
            if heading_lower == pattern or heading_lower.startswith(pattern):
                return category
    return None


def _extract_contact(header: str) -> ContactInfo:
    """Extract contact information from the header area."""
    contact = ContactInfo()

    # Email
    match = re.search(r"[\w.+-]+@[\w-]+\.[\w.-]+", header)
    if match:
        contact.email = match.group(0)

    # Phone (various formats)
    match = re.search(r"[\+]?[\d\s\-().]{7,15}", header)
    if match:
        phone = match.group(0).strip()
        # Avoid matching years or other short numbers
        if len(re.sub(r"[\s\-().+]", "", phone)) >= 7:
            contact.phone = phone

    # LinkedIn
    match = re.search(r"(?:linkedin\.com/in/|linkedin:\s*)(\S+)", header, re.IGNORECASE)
    if match:
        contact.linkedin = match.group(1).rstrip(")")

    # GitHub
    match = re.search(r"(?:github\.com/|github:\s*)(\S+)", header, re.IGNORECASE)
    if match:
        contact.github = match.group(1).rstrip(")")

    # Website
    match = re.search(r"https?://(?!.*(?:linkedin|github))[\w./\-]+", header)
    if match:
        contact.website = match.group(0)

    # Address - look for lines that seem like addresses (contain comma or city/state patterns)
    for line in header.split("\n"):
        line = line.strip().strip("|").strip("-").strip()
        if re.search(r"\b[A-Z]{2}\b.*\d{5}", line) or re.search(r",\s*\w+,\s*\w+", line):
            contact.address = line
            break

    return contact


def _parse_experience(content: str) -> list[WorkEntry]:
    """Parse work experience entries."""
    entries: list[WorkEntry] = []

    # Split by H3 headings (### Company / Role)
    h3_pattern = re.compile(r"^###\s+(.+)$", re.MULTILINE)
    h3_matches = list(h3_pattern.finditer(content))

    if h3_matches:
        for i, match in enumerate(h3_matches):
            start = match.end()
            end = h3_matches[i + 1].start() if i + 1 < len(h3_matches) else len(content)
            block = content[start:end].strip()
            heading = match.group(1).strip()
            entry = _parse_work_block(heading, block)
            entries.append(entry)
        return entries

    # Try bold heading pattern: **Company** | Title  (on its own line)
    bold_entry_pattern = re.compile(
        r"^\*\*(.+?)\*\*\s*(?:\|\s*(.+))?$", re.MULTILINE
    )
    bold_matches = list(bold_entry_pattern.finditer(content))

    if bold_matches:
        for i, match in enumerate(bold_matches):
            start = match.end()
            end = bold_matches[i + 1].start() if i + 1 < len(bold_matches) else len(content)
            block = content[start:end].strip()
            heading_company = match.group(1).strip()
            heading_title = match.group(2).strip() if match.group(2) else None
            entry = _parse_work_block_multiline(heading_company, heading_title, block)
            entries.append(entry)
        return entries

    # Fallback: split by bold lines or patterns
    blocks = _split_by_entries(content)
    for heading, block in blocks:
        entry = _parse_work_block(heading, block)
        entries.append(entry)

    return entries


def _parse_work_block(heading: str, block: str) -> WorkEntry:
    """Parse a single work experience block from a single-line heading."""
    entry = WorkEntry(company=heading)

    # Try to split heading: "Company | Title | Dates" or "Company - Title"
    parts = re.split(r"\s*[|]\s*", heading)
    if len(parts) == 1:
        parts = re.split(r"\s*[–—]\s*", heading)
    if len(parts) >= 2:
        entry.company = parts[0].strip().strip("*")
        entry.title = parts[1].strip().strip("*")
    if len(parts) >= 3:
        entry.start_date, entry.end_date = _parse_date_range(parts[2].strip())

    # Look for dates in the block if not found in heading
    if not entry.start_date:
        _extract_dates_from_block(entry, block)

    # Look for title in block if not found in heading
    if not entry.title:
        # Check for italic or bold text that might be a title
        title_match = re.search(r"[*_]{1,2}([^*_]+)[*_]{1,2}", block)
        if title_match:
            entry.title = title_match.group(1)

    # Extract bullet points
    entry.bullets = _parse_list_items(block)

    return entry


def _parse_work_block_multiline(
    company: str, title: str | None, block: str
) -> WorkEntry:
    """Parse a work block where company/title are on one line, dates on next.

    Handles format like:
        **Company**  |  Title
        May 2023 – Present  |  Location
        *Description...*
        * bullet 1
        * bullet 2
    """
    entry = WorkEntry(company=company)
    entry.title = title

    # Look for dates and location on the first non-empty line of the block
    _extract_dates_from_block(entry, block)

    # Look for location after date on same line (e.g. "May 2023 – Present  |  Tokyo, Japan")
    date_line_match = re.search(
        r"(?:\w+\.?\s+\d{4})\s*[-–—]+\s*(?:\w+\.?\s+\d{4}|[Pp]resent|[Cc]urrent)"
        r"\s*\|\s*(.+)",
        block,
    )
    if date_line_match:
        entry.location = date_line_match.group(1).strip()

    # Extract bullet points
    entry.bullets = _parse_list_items(block)

    return entry


def _extract_dates_from_block(entry: WorkEntry, block: str) -> None:
    """Extract start/end dates from block text into entry."""
    date_match = re.search(
        r"(\w+\.?\s+\d{4})\s*[-–—]+\s*(\w+\.?\s+\d{4}|[Pp]resent|[Cc]urrent)",
        block,
    )
    if date_match:
        entry.start_date = date_match.group(1)
        entry.end_date = date_match.group(2)


def _parse_date_range(text: str) -> tuple[str | None, str | None]:
    """Parse a date range string into start and end dates."""
    text = text.strip()
    parts = re.split(r"\s*[-–—]\s*|\s+to\s+", text, maxsplit=1)
    if len(parts) == 2:
        return parts[0].strip(), parts[1].strip()
    if len(parts) == 1:
        return parts[0].strip(), None
    return None, None


def _parse_education(content: str) -> list[EducationEntry]:
    """Parse education entries."""
    entries: list[EducationEntry] = []

    # Split by H3 headings
    h3_pattern = re.compile(r"^###\s+(.+)$", re.MULTILINE)
    h3_matches = list(h3_pattern.finditer(content))

    if h3_matches:
        for i, match in enumerate(h3_matches):
            start = match.end()
            end = h3_matches[i + 1].start() if i + 1 < len(h3_matches) else len(content)
            block = content[start:end].strip()
            heading = match.group(1).strip()
            entry = _parse_education_block(heading, block)
            entries.append(entry)
    elif re.search(r"^\*\*(.+?)\*\*", content, re.MULTILINE):
        # Try bold heading pattern
        bold_pattern = re.compile(r"^\*\*(.+?)\*\*\s*(?:\|\s*(.+))?$", re.MULTILINE)
        bold_matches = list(bold_pattern.finditer(content))
        for i, match in enumerate(bold_matches):
            start = match.end()
            end = bold_matches[i + 1].start() if i + 1 < len(bold_matches) else len(content)
            block = content[start:end].strip()
            heading = match.group(1).strip()
            if match.group(2):
                heading += " | " + match.group(2).strip()
            entry = _parse_education_block(heading, block)
            entries.append(entry)
    else:
        # Try line-by-line parsing for simpler formats
        blocks = _split_by_entries(content)
        for heading, block in blocks:
            entry = _parse_education_block(heading, block)
            entries.append(entry)

    return entries


def _parse_education_block(heading: str, block: str) -> EducationEntry:
    """Parse a single education block."""
    entry = EducationEntry(institution=heading)

    # Try to split heading: "University | Degree | Date"
    parts = re.split(r"\s*[|–—-]\s*", heading)
    if len(parts) >= 1:
        entry.institution = parts[0].strip().strip("*")
    if len(parts) >= 2:
        entry.degree = parts[1].strip().strip("*")
    if len(parts) >= 3:
        entry.graduation_date = parts[2].strip()

    # Look for degree in block
    if not entry.degree:
        degree_match = re.search(
            r"((?:B\.?S\.?|M\.?S\.?|Ph\.?D\.?|B\.?A\.?|M\.?A\.?|MBA|Bachelor|Master|Doctor)\w*"
            r"(?:\s+(?:of|in)\s+\w[\w\s,]*)?)",
            block,
            re.IGNORECASE,
        )
        if degree_match:
            entry.degree = degree_match.group(1).strip()

    # Look for field of study
    field_match = re.search(r"(?:in|of)\s+([A-Z][\w\s]+?)(?:\n|$|,|\|)", block)
    if field_match and not entry.field:
        entry.field = field_match.group(1).strip()

    # Look for dates
    if not entry.graduation_date:
        date_match = re.search(r"(\d{4})", block)
        if date_match:
            entry.graduation_date = date_match.group(1)

    # Look for GPA
    gpa_match = re.search(r"GPA:?\s*([\d.]+)", block, re.IGNORECASE)
    if gpa_match:
        entry.gpa = gpa_match.group(1)

    return entry


def _parse_skills(content: str) -> list[str]:
    """Parse skills from various formats (bullets, commas, categories)."""
    skills: list[str] = []

    for line in content.strip().split("\n"):
        line = line.strip()
        if not line:
            continue

        # Remove bold category labels like "**Languages:**" before bullet removal
        line = re.sub(r"^\*\*[^*]+:\*\*\s*", "", line)
        line = re.sub(r"^\*\*[^*]+\*\*:?\s*", "", line)
        # Remove bullet markers (but not ** which is bold)
        line = re.sub(r"^[-•]\s+", "", line)
        line = re.sub(r"^\*\s+(?!\*)", "", line)
        # Remove non-bold category labels like "Languages:"
        if ":" in line and not re.search(r"[,;|]", line.split(":")[0]):
            line = re.sub(r"^[A-Za-z\s]+:\s*", "", line)

        if not line:
            continue

        # Split by commas, pipes, or semicolons
        for skill in re.split(r"\s*[,;|]\s*", line):
            skill = skill.strip().strip("*").strip()
            if skill and len(skill) > 1:
                skills.append(skill)

    return skills


def _parse_list_items(content: str) -> list[str]:
    """Extract bullet/list items from content."""
    items: list[str] = []
    for line in content.strip().split("\n"):
        line = line.strip()
        match = re.match(r"^[-*•]\s+(.+)$", line)
        if match:
            items.append(match.group(1).strip())
    return items


def _split_by_entries(content: str) -> list[tuple[str, str]]:
    """Split content into entries by bold lines or patterns.

    Returns list of (heading, block_content) tuples.
    """
    entries: list[tuple[str, str]] = []

    # Try bold-line pattern: **Company Name** or **Title**
    bold_pattern = re.compile(r"^\*\*(.+?)\*\*", re.MULTILINE)
    matches = list(bold_pattern.finditer(content))

    if matches:
        for i, match in enumerate(matches):
            heading = match.group(1).strip()
            start = match.end()
            end = matches[i + 1].start() if i + 1 < len(matches) else len(content)
            block = content[start:end].strip()
            entries.append((heading, block))
    else:
        # Fallback: treat each non-empty paragraph as an entry
        paragraphs = re.split(r"\n\n+", content.strip())
        for para in paragraphs:
            lines = para.strip().split("\n")
            if lines:
                heading = lines[0].strip().strip("*").strip("-").strip()
                block = "\n".join(lines[1:]) if len(lines) > 1 else ""
                if heading:
                    entries.append((heading, block))

    return entries
