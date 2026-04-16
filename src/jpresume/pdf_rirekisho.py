"""Rirekisho (履歴書) PDF renderer - standard Japanese resume form layout.

Uses reportlab for reliable CJK font rendering.
"""

from __future__ import annotations

from pathlib import Path

from pathlib import Path

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from jpresume.models import RirekishoData

# Find and register a Japanese TTF/TTC font
# Fonts with TrueType outlines (required by reportlab - no CFF/PostScript)
_FONT_PATHS = [
    # macOS system fonts with glyf outlines + Japanese coverage
    "/System/Library/Fonts/STHeiti Light.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
    # User-installed TTF fonts
    "/Library/Fonts/NotoSansJP-Regular.ttf",
    # Linux
    "/usr/share/fonts/truetype/noto/NotoSansCJKjp-Regular.ttf",
    "/opt/homebrew/share/fonts/NotoSansJP-Regular.ttf",
]

_BOLD_PATHS = [
    "/System/Library/Fonts/STHeiti Medium.ttc",
    "/Library/Fonts/NotoSansJP-Bold.ttf",
]

_font_registered = False
FONT = "Helvetica"  # fallback


def _register_fonts() -> None:
    global _font_registered, FONT
    if _font_registered:
        return
    _font_registered = True

    for path in _FONT_PATHS:
        if Path(path).exists():
            try:
                kwargs = {}
                if path.endswith(".ttc"):
                    kwargs["subfontIndex"] = 0
                pdfmetrics.registerFont(TTFont("JP", path, **kwargs))
                FONT = "JP"

                # Try bold variant
                for bold_path in _BOLD_PATHS:
                    if Path(bold_path).exists():
                        try:
                            bkw = {}
                            if bold_path.endswith(".ttc"):
                                bkw["subfontIndex"] = 0
                            pdfmetrics.registerFont(TTFont("JP-Bold", bold_path, **bkw))
                        except Exception:
                            pdfmetrics.registerFont(TTFont("JP-Bold", path, **kwargs))
                        break
                else:
                    pdfmetrics.registerFont(TTFont("JP-Bold", path, **kwargs))
                break
            except Exception:
                continue

# Character substitutions for fonts missing certain glyphs
_CHAR_SUBS = {
    "\u30FB": "\u00B7",  # ・ (katakana middle dot) -> · (middle dot)
}


def _sanitize(text: str) -> str:
    """Replace characters unsupported by the PDF font."""
    for orig, repl in _CHAR_SUBS.items():
        text = text.replace(orig, repl)
    return text


# Layout constants
PAGE_W, PAGE_H = A4  # 595.27 x 841.89 points (210 x 297 mm)
M = 10 * mm  # margin
CW = PAGE_W - 2 * M  # content width

# Photo
PHOTO_W = 30 * mm
PHOTO_H = 40 * mm

# Column widths for history tables
YEAR_W = 18 * mm
MONTH_W = 12 * mm
DESC_W = CW - YEAR_W - MONTH_W

# Row heights
ROW_H = 5.5 * mm
SMALL_H = 5 * mm


def render_rirekisho_pdf(data: RirekishoData, output_path: Path) -> None:
    """Render a RirekishoData model to a standard-format rirekisho PDF."""
    _register_fonts()

    # Sanitize all text fields for font compatibility
    data = data.model_copy(deep=True)
    for field_name in data.model_fields:
        val = getattr(data, field_name)
        if isinstance(val, str):
            setattr(data, field_name, _sanitize(val))
        elif isinstance(val, list):
            for i, item in enumerate(val):
                if isinstance(item, tuple):
                    val[i] = tuple(_sanitize(s) if isinstance(s, str) else s for s in item)

    c = canvas.Canvas(str(output_path), pagesize=A4)

    # Y coordinate starts from bottom in reportlab, so we track from top
    top = PAGE_H - M
    x0 = M
    y = top  # current y position (decreasing)

    # ===== TITLE =====
    c.setFont(FONT, 16)
    c.drawString(x0, y - 12, "履 歴 書")
    c.setFont(FONT, 8)
    c.drawRightString(x0 + CW, y - 8, data.creation_date)
    y -= 16

    # ===== PERSONAL INFO =====
    info_w = CW - PHOTO_W - 2 * mm
    label_w = 22 * mm

    # Furigana row
    furi_h = 5 * mm
    _draw_label_row(c, x0, y, info_w, furi_h, label_w, "ふりがな",
                    data.name_furigana or "", label_size=6, value_size=6)
    y -= furi_h

    # Name row
    name_h = 12 * mm
    _draw_label_row(c, x0, y, info_w, name_h, label_w, "氏　名",
                    data.name_kanji or "", label_size=7, value_size=14, bold=True)
    y -= name_h

    # DOB / Gender
    dob_h = 7 * mm
    dob_text = f"生年月日　{data.date_of_birth or ''}"
    if data.gender:
        dob_text += f"　　　　性別　{data.gender}"
    _draw_box(c, x0, y, info_w, dob_h)
    c.setFont(FONT, 7)
    c.drawString(x0 + 2 * mm, y - dob_h / 2 - 2, dob_text)
    y -= dob_h

    # Photo box
    photo_x = x0 + info_w + 2 * mm
    photo_y = y  # bottom of DOB row
    photo_top = photo_y + furi_h + name_h + dob_h
    _draw_box(c, photo_x, photo_y, PHOTO_W, photo_top - photo_y)
    if data.photo_path and Path(data.photo_path).exists():
        c.drawImage(data.photo_path, photo_x + 1 * mm, photo_y + 1 * mm,
                    PHOTO_W - 2 * mm, photo_top - photo_y - 2 * mm)
    else:
        c.setFont(FONT, 7)
        mid_y = photo_y + (photo_top - photo_y) / 2
        c.drawCentredString(photo_x + PHOTO_W / 2, mid_y + 2, "写真")
        c.setFont(FONT, 5)
        c.drawCentredString(photo_x + PHOTO_W / 2, mid_y - 5, "(3×4cm)")

    # Address furigana
    addr_furi_h = SMALL_H
    postal = f"〒{data.postal_code}　" if data.postal_code else ""
    _draw_label_row(c, x0, y, CW, addr_furi_h, label_w, "ふりがな",
                    postal + (data.address_furigana or ""), label_size=6, value_size=5)
    y -= addr_furi_h

    # Address
    addr_h = 10 * mm
    _draw_label_row(c, x0, y, CW, addr_h, label_w, "現住所",
                    data.address or "", label_size=7, value_size=8)
    y -= addr_h

    # Phone / Email
    contact_h = 7 * mm
    half_w = CW / 2
    tel_lbl = 16 * mm
    _draw_label_row(c, x0, y, half_w, contact_h, tel_lbl, "電話",
                    data.phone or "", label_size=6, value_size=8)
    _draw_label_row(c, x0 + half_w, y, half_w, contact_h, tel_lbl, "E-mail",
                    data.email or "", label_size=6, value_size=7)
    y -= contact_h

    # Contact address (if different)
    if data.contact_address:
        _draw_label_row(c, x0, y, CW, addr_furi_h, label_w, "ふりがな",
                        (data.contact_address_furigana or ""),
                        label_size=6, value_size=5)
        y -= addr_furi_h
        _draw_label_row(c, x0, y, CW, addr_h, label_w, "連絡先",
                        data.contact_address or "", label_size=7, value_size=8)
        y -= addr_h

    y -= 1 * mm

    # ===== EDUCATION & WORK HISTORY =====
    # Section header
    hdr_h = 6 * mm
    _draw_box(c, x0, y, CW, hdr_h, fill=True)
    c.setFont(FONT, 9)
    c.drawCentredString(x0 + CW / 2, y - hdr_h / 2 - 3, "学歴·職歴")
    y -= hdr_h

    # Column headers
    col_h = SMALL_H
    _draw_three_cols(c, x0, y, col_h)
    c.setFont(FONT, 6)
    c.drawCentredString(x0 + YEAR_W / 2, y - col_h / 2 - 2, "年")
    c.drawCentredString(x0 + YEAR_W + MONTH_W / 2, y - col_h / 2 - 2, "月")
    c.drawCentredString(x0 + YEAR_W + MONTH_W + DESC_W / 2, y - col_h / 2 - 2, "学歴·職歴")
    y -= col_h

    # Build history entries
    entries: list[tuple[str, str, str]] = []
    entries.append(("", "", "学　歴"))
    for d, desc in data.education_history:
        yr, mo = _split_ym(d)
        entries.append((yr, mo, desc))
    entries.append(("", "", ""))
    entries.append(("", "", "職　歴"))
    for d, desc in data.work_history:
        yr, mo = _split_ym(d)
        entries.append((yr, mo, desc))
    entries.append(("", "", "以上"))

    num_rows = max(20, len(entries))
    for i in range(num_rows):
        _draw_three_cols(c, x0, y, ROW_H)
        if i < len(entries):
            yr, mo, desc = entries[i]
            c.setFont(FONT, 6)
            c.drawCentredString(x0 + YEAR_W / 2, y - ROW_H / 2 - 2, yr)
            c.drawCentredString(x0 + YEAR_W + MONTH_W / 2, y - ROW_H / 2 - 2, mo)
            is_header = desc in ("学　歴", "職　歴")
            is_end = desc == "以上"
            if is_header:
                c.drawCentredString(x0 + YEAR_W + MONTH_W + DESC_W / 2, y - ROW_H / 2 - 2, desc)
            elif is_end:
                c.drawRightString(x0 + CW - 3 * mm, y - ROW_H / 2 - 2, desc)
            else:
                c.drawString(x0 + YEAR_W + MONTH_W + 2 * mm, y - ROW_H / 2 - 2, desc)
        y -= ROW_H

    y -= 1 * mm

    # ===== LICENSES =====
    lic_hdr_h = 6 * mm
    _draw_box(c, x0, y, CW, lic_hdr_h, fill=True)
    c.setFont(FONT, 8)
    c.drawCentredString(x0 + CW / 2, y - lic_hdr_h / 2 - 2, "免許·資格")
    y -= lic_hdr_h

    _draw_three_cols(c, x0, y, col_h)
    c.setFont(FONT, 6)
    c.drawCentredString(x0 + YEAR_W / 2, y - col_h / 2 - 2, "年")
    c.drawCentredString(x0 + YEAR_W + MONTH_W / 2, y - col_h / 2 - 2, "月")
    c.drawCentredString(x0 + YEAR_W + MONTH_W + DESC_W / 2, y - col_h / 2 - 2, "免許·資格")
    y -= col_h

    lic_entries = []
    for d, name in data.licenses:
        yr, mo = _split_ym(d)
        lic_entries.append((yr, mo, name))

    for i in range(3):
        _draw_three_cols(c, x0, y, ROW_H)
        if i < len(lic_entries):
            yr, mo, name = lic_entries[i]
            c.setFont(FONT, 6)
            c.drawCentredString(x0 + YEAR_W / 2, y - ROW_H / 2 - 2, yr)
            c.drawCentredString(x0 + YEAR_W + MONTH_W / 2, y - ROW_H / 2 - 2, mo)
            c.drawString(x0 + YEAR_W + MONTH_W + 2 * mm, y - ROW_H / 2 - 2, name)
        y -= ROW_H

    y -= 1 * mm

    # ===== BOTTOM SECTION =====

    # Motivation
    mot_h = 22 * mm
    _draw_box(c, x0, y, CW, mot_h)
    lbl_h = 5 * mm
    c.setFillGray(0.96)
    c.rect(x0, y - lbl_h, CW, lbl_h, fill=1, stroke=1)
    c.setFillGray(0)
    c.setFont(FONT, 6)
    c.drawString(x0 + 2 * mm, y - lbl_h + 1.5 * mm,
                 "志望の動機、特技、好きな学科、アピールポイントなど")
    c.setFont(FONT, 7)
    _draw_wrapped_text(c, x0 + 2 * mm, y - lbl_h - 4 * mm,
                       CW - 4 * mm, data.motivation or "", 7, 4 * mm)
    y -= mot_h

    # Hobbies
    if data.hobbies:
        hob_h = 10 * mm
        hob_lbl_w = 28 * mm
        _draw_box(c, x0, y, CW, hob_h)
        c.setFillGray(0.96)
        c.rect(x0, y - hob_h, hob_lbl_w, hob_h, fill=1, stroke=1)
        c.setFillGray(0)
        c.setFont(FONT, 7)
        c.drawCentredString(x0 + hob_lbl_w / 2, y - hob_h / 2 - 2, "趣味·特技")
        c.setFont(FONT, 8)
        c.drawString(x0 + hob_lbl_w + 2 * mm, y - hob_h / 2 - 2, data.hobbies)
        y -= hob_h

    # Bottom info row
    bot_h = 12 * mm
    lbl_h2 = 5 * mm
    col_w = CW / 4

    items = [
        ("通勤時間", data.commute_time or ""),
        ("扶養家族", f"{data.dependents_excl_spouse}人" if data.dependents_excl_spouse is not None else ""),
        ("配偶者", "有" if data.spouse is True else ("無" if data.spouse is False else "")),
        ("扶養家族数", f"{data.dependents}人" if data.dependents is not None else ""),
    ]

    for idx, (label, value) in enumerate(items):
        bx = x0 + idx * col_w
        _draw_box(c, bx, y, col_w, bot_h)
        c.setFillGray(0.96)
        c.rect(bx, y - lbl_h2, col_w, lbl_h2, fill=1, stroke=1)
        c.setFillGray(0)
        c.setFont(FONT, 6)
        c.drawCentredString(bx + col_w / 2, y - lbl_h2 + 1.5 * mm, label)
        c.setFont(FONT, 8)
        c.drawCentredString(bx + col_w / 2, y - bot_h / 2 - 4, value)

    c.save()


# --- Helper functions ---


def _draw_box(c: canvas.Canvas, x: float, y: float, w: float, h: float,
              fill: bool = False) -> None:
    """Draw a rectangle. y is the TOP edge (reportlab y increases upward)."""
    if fill:
        c.setFillGray(0.96)
        c.rect(x, y - h, w, h, fill=1, stroke=1)
        c.setFillGray(0)
    else:
        c.rect(x, y - h, w, h, fill=0, stroke=1)


def _draw_label_row(c: canvas.Canvas, x: float, y: float, w: float, h: float,
                    label_w: float, label: str, value: str,
                    label_size: float = 6, value_size: float = 8,
                    bold: bool = False) -> None:
    """Draw a row with a shaded label on the left and value on the right."""
    # Full border
    c.rect(x, y - h, w, h)
    # Label background
    c.setFillGray(0.96)
    c.rect(x, y - h, label_w, h, fill=1, stroke=1)
    c.setFillGray(0)
    # Label text
    c.setFont(FONT, label_size)
    c.drawCentredString(x + label_w / 2, y - h / 2 - label_size * 0.15, label)
    # Value text
    c.setFont(FONT, value_size)
    c.drawString(x + label_w + 2 * mm, y - h / 2 - value_size * 0.15, value)


def _draw_three_cols(c: canvas.Canvas, x: float, y: float, h: float) -> None:
    """Draw a three-column row for history tables."""
    c.rect(x, y - h, YEAR_W, h)
    c.rect(x + YEAR_W, y - h, MONTH_W, h)
    c.rect(x + YEAR_W + MONTH_W, y - h, DESC_W, h)


def _draw_wrapped_text(c: canvas.Canvas, x: float, y: float,
                       max_w: float, text: str, font_size: float,
                       line_h: float) -> None:
    """Draw text with simple word wrapping."""
    c.setFont(FONT, font_size)
    # Simple character-based wrapping for Japanese text
    chars_per_line = int(max_w / (font_size * 0.6))
    lines = []
    while text:
        lines.append(text[:chars_per_line])
        text = text[chars_per_line:]
    for i, line in enumerate(lines):
        c.drawString(x, y - i * line_h, line)


def _split_ym(date_str: str) -> tuple[str, str]:
    """Split '2020年4月' into ('2020', '4')."""
    if not date_str:
        return ("", "")
    import re
    m = re.match(r"(.+?)年(\d+)月?$", date_str.strip())
    if m:
        return (m.group(1), m.group(2))
    m = re.match(r"(.+?)年$", date_str.strip())
    if m:
        return (m.group(1), "")
    return (date_str, "")
