"""PDF generation from markdown using fpdf2 (pure Python, no system deps)."""

from __future__ import annotations

import re
from pathlib import Path

from fpdf import FPDF


# Japanese font search paths
_FONT_CANDIDATES = [
    # macOS
    "/System/Library/Fonts/ヒラギノ角ゴシック W3.ttc",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/Library/Fonts/NotoSansCJKjp-Regular.otf",
    "/Library/Fonts/NotoSansJP-Regular.ttf",
    "/System/Library/Fonts/Supplemental/Arial Unicode.ttf",
    # Linux
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",
    "/usr/share/fonts/noto-cjk/NotoSansCJKjp-Regular.otf",
    # Homebrew
    "/opt/homebrew/share/fonts/NotoSansCJKjp-Regular.otf",
]

_FONT_CANDIDATES_BOLD = [
    "/System/Library/Fonts/ヒラギノ角ゴシック W6.ttc",
    "/Library/Fonts/NotoSansCJKjp-Bold.otf",
    "/Library/Fonts/NotoSansJP-Bold.ttf",
    "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    "/opt/homebrew/share/fonts/NotoSansCJKjp-Bold.otf",
]


def _extract_ttf_from_ttc(ttc_path: str) -> str | None:
    """Extract the first font from a TTC file as a standalone TTF."""
    import tempfile
    try:
        from fontTools.ttLib import TTFont
        font = TTFont(ttc_path, fontNumber=0)
        ttf_path = Path(tempfile.gettempdir()) / f"jpresume_{Path(ttc_path).stem}.ttf"
        if not ttf_path.exists():
            font.save(str(ttf_path))
        font.close()
        return str(ttf_path)
    except Exception:
        return None


def _find_font(candidates: list[str]) -> str | None:
    for path in candidates:
        if Path(path).exists():
            if path.endswith(".ttc"):
                extracted = _extract_ttf_from_ttc(path)
                if extracted:
                    return extracted
            return path
    return None


class JapaneseResumePDF(FPDF):
    """PDF generator with Japanese font support."""

    def __init__(self) -> None:
        super().__init__()
        self.set_auto_page_break(auto=True, margin=15)

        # Register Japanese font
        font_path = _find_font(_FONT_CANDIDATES)
        if font_path:
            self.add_font("jp", "", font_path, uni=True)
            bold_path = _find_font(_FONT_CANDIDATES_BOLD)
            if bold_path:
                self.add_font("jp", "B", bold_path, uni=True)
            else:
                self.add_font("jp", "B", font_path, uni=True)
            self._font_family = "jp"
        else:
            # Fallback - PDF will work but Japanese chars may not render
            self._font_family = "Helvetica"

    def _set_font(self, style: str = "", size: int = 10) -> None:
        self.set_font(self._font_family, style, size)


def markdown_to_pdf(markdown_text: str, output_path: Path) -> None:
    """Convert markdown text to PDF with Japanese support."""
    pdf = JapaneseResumePDF()
    pdf.add_page()

    lines = markdown_text.split("\n")
    in_table = False
    table_rows: list[list[str]] = []

    for line in lines:
        stripped = line.strip()

        # Skip empty lines
        if not stripped:
            if in_table:
                _flush_table(pdf, table_rows)
                table_rows = []
                in_table = False
            pdf.ln(2)
            continue

        # Horizontal rule
        if stripped.startswith("---"):
            if in_table:
                _flush_table(pdf, table_rows)
                table_rows = []
                in_table = False
            pdf.ln(2)
            pdf.set_draw_color(200, 200, 200)
            pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
            pdf.ln(4)
            continue

        # Table rows
        if "|" in stripped and not stripped.startswith("#"):
            # Skip separator rows like |------|------|
            if re.match(r"^\|[\s\-:|]+\|$", stripped):
                continue
            cells = [c.strip() for c in stripped.split("|")]
            cells = [c for c in cells if c]  # remove empty from leading/trailing |
            if cells:
                in_table = True
                table_rows.append(cells)
            continue

        # Flush any pending table
        if in_table:
            _flush_table(pdf, table_rows)
            table_rows = []
            in_table = False

        # H1
        if stripped.startswith("# ") and not stripped.startswith("## "):
            text = _strip_md(stripped[2:])
            pdf._set_font("B", 16)
            pdf.cell(0, 10, text, align="C", new_x="LMARGIN", new_y="NEXT")
            pdf.set_draw_color(50, 50, 50)
            pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
            pdf.ln(4)
            continue

        # H2
        if stripped.startswith("## "):
            text = _strip_md(stripped[3:])
            pdf._set_font("B", 12)
            pdf.ln(4)
            pdf.cell(0, 8, text, new_x="LMARGIN", new_y="NEXT")
            pdf.set_draw_color(100, 100, 100)
            pdf.line(pdf.l_margin, pdf.get_y(), pdf.w - pdf.r_margin, pdf.get_y())
            pdf.ln(3)
            continue

        # H3
        if stripped.startswith("### "):
            text = _strip_md(stripped[4:])
            pdf._set_font("B", 11)
            pdf.ln(3)
            pdf.cell(0, 7, text, new_x="LMARGIN", new_y="NEXT")
            pdf.ln(2)
            continue

        # Bullet points
        if stripped.startswith(("- ", "* ")):
            text = _strip_md(stripped[2:])
            pdf._set_font("", 9)
            indent = 5
            bullet_w = 4
            text_w = pdf.w - pdf.l_margin - pdf.r_margin - indent - bullet_w
            if text_w < 20:
                text_w = pdf.w - pdf.l_margin - pdf.r_margin
            pdf.set_x(pdf.l_margin + indent)
            pdf.cell(bullet_w, 5, "・")
            pdf.multi_cell(text_w, 5, text)
            continue

        # Bold line (like **作成日**: value)
        if stripped.startswith("**"):
            text = _strip_md(stripped)
            pdf._set_font("", 9)
            pdf.set_x(pdf.l_margin)
            pdf.multi_cell(pdf.w - pdf.l_margin - pdf.r_margin, 5, text)
            continue

        # Regular paragraph
        text = _strip_md(stripped)
        pdf._set_font("", 9)
        pdf.set_x(pdf.l_margin)
        pdf.multi_cell(pdf.w - pdf.l_margin - pdf.r_margin, 5, text)

    # Flush remaining table
    if in_table:
        _flush_table(pdf, table_rows)

    pdf.output(str(output_path))


def _flush_table(pdf: JapaneseResumePDF, rows: list[list[str]]) -> None:
    """Render a markdown table as a PDF table."""
    if not rows:
        return

    page_width = pdf.w - pdf.l_margin - pdf.r_margin
    num_cols = max(len(r) for r in rows)

    if num_cols == 2:
        col_widths = [page_width * 0.25, page_width * 0.75]
    else:
        col_widths = [page_width / num_cols] * num_cols

    pdf._set_font("", 8)
    pdf.set_draw_color(150, 150, 150)

    for row in rows:
        row_height = 6
        # Calculate needed height for multi-line cells
        for i, cell in enumerate(row):
            w = col_widths[i] if i < len(col_widths) else col_widths[-1]
            text = _strip_md(cell)
            lines_needed = max(1, len(text) * pdf.font_size / w + 1)
            row_height = max(row_height, int(lines_needed * 5))

        for i, cell in enumerate(row):
            w = col_widths[i] if i < len(col_widths) else col_widths[-1]
            text = _strip_md(cell)
            x = pdf.get_x()
            y = pdf.get_y()
            pdf.rect(x, y, w, row_height)
            pdf.set_xy(x + 1, y + 1)
            pdf.multi_cell(w - 2, 5, text)
            pdf.set_xy(x + w, y)

        pdf.ln(row_height)


def _strip_md(text: str) -> str:
    """Remove markdown formatting from text."""
    text = re.sub(r"\*\*(.+?)\*\*", r"\1", text)  # bold
    text = re.sub(r"\*(.+?)\*", r"\1", text)  # italic
    text = re.sub(r"__(.+?)__", r"\1", text)
    text = re.sub(r"_(.+?)_", r"\1", text)
    text = re.sub(r"\[(.+?)\]\(.+?\)", r"\1", text)  # links
    text = re.sub(r"\\([+])", r"\1", text)  # escaped chars
    return text.strip()
