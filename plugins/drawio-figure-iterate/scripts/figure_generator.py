#!/usr/bin/env python3
"""Reusable primitives for generating overflow-proof draw.io figures.

Hand-sized chip geometries are fragile: a text edit silently overflows its box,
and you only notice after re-rendering. This module measures text with real PIL
font metrics so chip heights are computed, not guessed, and the page-overflow
guard turns a too-tall layout into a build error instead of a silent bleed.

Use it as a library (import the helpers) or run it directly to emit a small
demo figure next to this file.

Primitives:
    font(size)                      cached PIL FreeTypeFont
    strip_html(text)                drawio inline HTML -> plain text
    wrap_lines(text, fs, max_w)     greedy word-wrap against real bbox widths
    line_height(fs)                 per-line spacing tuned to drawio
    text_block_height(...)          measured height of a wrapped text block
    xml_attr(s)                     escape a value for an XML attribute
    cell(...) / arrow_cell(...)     emit mxCell vertices / edges
    Page(...)                       page wrapper + overflow guard

See README and the iterate skill for the full author -> export -> score loop.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from PIL import ImageFont

# --------------------------------------------------------------------------
# Tunables. LINE_HEIGHT_FACTOR matches drawio's per-line spacing; the italic
# bump widens measurement slightly for <i>...</i> spans (italics run wider).
# --------------------------------------------------------------------------
LINE_HEIGHT_FACTOR = 1.22
ITALIC_WIDTH_BUMP = 0.04
WIDTH_SAFETY = 1.00

# drawio defaults to Helvetica; DejaVuSans is the closest commonly-installed
# match on Linux. Override via the FIGURE_FONT_PATH env var if needed.
import os

FONT_PATH = os.environ.get(
    "FIGURE_FONT_PATH", "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
)

_font_cache: dict[int, ImageFont.FreeTypeFont] = {}


def font(size: int) -> ImageFont.FreeTypeFont:
    f = _font_cache.get(size)
    if f is None:
        f = ImageFont.truetype(FONT_PATH, size)
        _font_cache[size] = f
    return f


def strip_html(text: str) -> str:
    text = text.replace("&#10;", "\n")
    text = re.sub(r"<[^>]+>", "", text)
    return (
        text.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&amp;", "&")
        .replace("&nbsp;", " ")
    )


def _italic_fraction(html: str) -> float:
    plain = strip_html(html)
    if not plain:
        return 0.0
    italic_chars = 0
    for m in re.finditer(r"<i>(.*?)</i>", html, flags=re.IGNORECASE | re.DOTALL):
        italic_chars += len(strip_html(m.group(1)))
    return italic_chars / max(len(plain), 1)


def wrap_lines(text: str, fs: int, max_width: float) -> list[str]:
    """Greedy word-wrap against measured pixel widths at font size `fs`."""
    f = font(fs)
    plain = strip_html(text)
    italic_bump = 1.0 + ITALIC_WIDTH_BUMP * _italic_fraction(text)

    def width_of(s: str) -> float:
        if not s:
            return 0.0
        bbox = f.getbbox(s)
        return (bbox[2] - bbox[0]) * italic_bump * WIDTH_SAFETY

    out: list[str] = []
    for para in plain.split("\n"):
        if not para.strip():
            out.append("")
            continue
        words = para.split(" ")
        cur = ""
        for w in words:
            test = (cur + " " + w) if cur else w
            if width_of(test) <= max_width or not cur:
                cur = test
            else:
                out.append(cur)
                cur = w
        if cur:
            out.append(cur)
    return out


def line_height(fs: int) -> int:
    return int(round(fs * LINE_HEIGHT_FACTOR))


def text_block_height(
    text: str, fs: int, usable_w: float, top_pad: int, bottom_pad: int
) -> int:
    n = max(1, len(wrap_lines(text, fs, usable_w)))
    return top_pad + n * line_height(fs) + bottom_pad


# --------------------------------------------------------------------------
# XML emission. The escape in xml_attr is load-bearing: a raw `<b>` inside an
# attribute value produces malformed XML and drawio silently drops the entire
# <mxGraphModel> on import (the PNG renders only the title band).
# --------------------------------------------------------------------------
def xml_attr(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
        .replace("\n", "&#10;")
    )


def cell(cell_id: str, value: str, style: str, x: int, y: int, w: int, h: int) -> str:
    return (
        f'        <mxCell id="{cell_id}" parent="1" value="{xml_attr(value)}" '
        f'style="{style}" vertex="1">\n'
        f'          <mxGeometry x="{x}" y="{y}" width="{w}" height="{h}" as="geometry" />\n'
        f"        </mxCell>\n"
    )


def arrow_cell(
    cell_id: str, x1: int, y1: int, x2: int, y2: int, colour: str, width: float = 1.5
) -> str:
    style = (
        f"endArrow=classic;html=1;rounded=0;strokeColor={colour};"
        f"strokeWidth={width};"
    )
    return (
        f'        <mxCell id="{cell_id}" parent="1" style="{style}" edge="1">\n'
        f'          <mxGeometry relative="1" as="geometry">\n'
        f'            <mxPoint x="{x1}" y="{y1}" as="sourcePoint" />\n'
        f'            <mxPoint x="{x2}" y="{y2}" as="targetPoint" />\n'
        f"          </mxGeometry>\n"
        f"        </mxCell>\n"
    )


@dataclass
class Page:
    """Wraps emitted cells in a draw.io page and guards against overflow."""

    width: int
    height: int
    name: str = "Figure"
    diagram_id: str = "figure"
    agent: str = "figure-generator"
    background: str = "none"
    _cells: list[str] = field(default_factory=list)

    def add(self, xml: str) -> None:
        self._cells.append(xml)

    def render(self, y_final: int) -> str:
        if y_final > self.height:
            raise SystemExit(
                f"ERROR: layout overflows the page by {y_final - self.height} px "
                f"(content reaches y={y_final}, page height={self.height}). "
                "Trim text, reduce padding, or grow the page."
            )
        return (
            f'<mxfile host="app.diagrams.net" agent="{self.agent}">\n'
            f'  <diagram id="{self.diagram_id}" name="{xml_attr(self.name)}">\n'
            f'    <mxGraphModel dx="438" dy="325" grid="1" gridSize="10" guides="1" '
            f'tooltips="1" connect="1" arrows="1" fold="1" page="1" pageScale="1" '
            f'pageWidth="{self.width}" pageHeight="{self.height}" '
            f'background="{self.background}" math="0" shadow="0">\n'
            "      <root>\n"
            '        <mxCell id="0" />\n'
            '        <mxCell id="1" parent="0" />\n'
            + "".join(self._cells)
            + "      </root>\n"
            "    </mxGraphModel>\n"
            "  </diagram>\n"
            "</mxfile>\n"
        )


# --------------------------------------------------------------------------
# Demo: a measured three-box horizontal flow, sized to fit A4 portrait width.
# Run `python3 figure_generator.py` to emit figure_generator_demo.drawio, then
# export it with scripts/export_png.sh.
# --------------------------------------------------------------------------
def _demo() -> str:
    PAGE_W, PAGE_H = 820, 300
    MARGIN = 16
    page = Page(PAGE_W, PAGE_H, name="figure_generator demo", diagram_id="demo")

    y = MARGIN
    title = "figure_generator demo: measured three-stage flow"
    page.add(
        cell(
            "title",
            title,
            "text;html=1;fontSize=20;fontStyle=1;align=center;verticalAlign=middle;"
            "whiteSpace=wrap;fontColor=#1f1f1f;",
            MARGIN,
            y,
            PAGE_W - 2 * MARGIN,
            30,
        )
    )
    y += 30 + 16

    boxes = [
        ("Author", "Emit mxGraph XML; chip heights computed from PIL font metrics."),
        ("Export", "Headless draw.io CLI renders a PNG at print scale."),
        ("Score", "Read the PNG, check legibility against the requirements doc."),
    ]
    n = len(boxes)
    gap = 24
    bw = (PAGE_W - 2 * MARGIN - (n - 1) * gap) // n
    usable = bw - 24

    body_h = max(
        text_block_height(b, 13, usable, top_pad=8, bottom_pad=8) for _, b in boxes
    )
    box_h = 28 + body_h

    for i, (label, body) in enumerate(boxes):
        bx = MARGIN + i * (bw + gap)
        page.add(
            cell(
                f"box{i}_frame",
                "",
                "rounded=2;whiteSpace=wrap;html=1;fillColor=#eaf1fb;"
                "strokeColor=#6c8ebf;strokeWidth=2;",
                bx,
                y,
                bw,
                box_h,
            )
        )
        page.add(
            cell(
                f"box{i}_hdr",
                label,
                "rounded=0;whiteSpace=wrap;html=1;fillColor=#6c8ebf;"
                "strokeColor=#6c8ebf;align=center;verticalAlign=middle;fontStyle=1;"
                "fontSize=15;fontColor=#ffffff;",
                bx,
                y,
                bw,
                28,
            )
        )
        page.add(
            cell(
                f"box{i}_body",
                body,
                "text;html=1;align=left;verticalAlign=middle;spacingLeft=12;"
                "spacingRight=12;fontSize=13;fontColor=#1f1f1f;whiteSpace=wrap;",
                bx,
                y + 28,
                bw,
                box_h - 28,
            )
        )
        if i < n - 1:
            ay = y + 14
            page.add(
                arrow_cell(
                    f"arr{i}",
                    bx + bw + 1,
                    ay,
                    bx + bw + gap - 1,
                    ay,
                    "#555555",
                    width=2.0,
                )
            )

    y_final = y + box_h + MARGIN
    return page.render(y_final)


if __name__ == "__main__":
    out = Path(__file__).parent / "figure_generator_demo.drawio"
    out.write_text(_demo())
    print(f"Wrote {out}")
    print("Export it with: scripts/export_png.sh", out, "/tmp/demo.png 2")
