#!/usr/bin/env python3
"""Worked example: a compact 3-column "phase strip" figure.

This is a real-world generator (lightly genericised from a technical-disclosure
figure) showing how to use the figure_generator primitives for a multi-chip
layout where every chip's height is measured, not guessed. Each phase is a
column; each column stacks labelled rows (REPORTED / ENTRY / EXIT / NOTE).

It uses a consistent colour vocabulary (one hue per phase), auto-sizes every
row from its wrapped body text, and raises SystemExit if the laid-out page
overflows, so a text edit that no longer fits fails the build instead of
silently bleeding off the page.

Run:
    python3 examples/three_phase_strip.py
    scripts/export_png.sh examples/three_phase_strip.drawio examples/three_phase_strip.png 2
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path

# Make scripts/ importable when run from the repo root.
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts"))

from figure_generator import (  # noqa: E402
    Page,
    arrow_cell,
    cell,
    line_height,
    text_block_height,
    wrap_lines,
)

# ---- page / layout constants --------------------------------------------
PAGE_W, PAGE_H = 820, 560
MARGIN_X = 10
TOP_MARGIN = 10

N_COLS = 3
COL_GAP = 14
COL_W = (PAGE_W - 2 * MARGIN_X - (N_COLS - 1) * COL_GAP) // N_COLS
COL_PAD_LR = 12
COL_USABLE = COL_W - 2 * COL_PAD_LR

PHASE_HEADER_H = 32
ROW_LABEL_OFFSET = 18
ROW_BOTTOM_PAD = 10
ROW_GAP = 4
TITLE_H = 30
CAPTION_MIN_H = 22
FOOTER_MIN_H = 22

FS_TITLE = 20
FS_CAPTION = 11
FS_PHASE_HEADER = 15
FS_LABEL = 10
FS_BODY = 13
FS_FOOTER = 10


def row_height(body_text: str) -> int:
    n = max(1, len(wrap_lines(body_text, FS_BODY, COL_USABLE)))
    return ROW_LABEL_OFFSET + n * line_height(FS_BODY) + ROW_BOTTOM_PAD


# ---- content -------------------------------------------------------------
@dataclass
class Phase:
    pid: str
    name: str
    border: str
    header_fill: str
    body_fill: str
    label_color: str
    rows: list[tuple[str, str]]


PHASES: list[Phase] = [
    Phase(
        "p1",
        "Phase 1 - Setup",
        "#6c8ebf",
        "#6c8ebf",
        "#eaf1fb",
        "#3f5d80",
        rows=[
            ("REPORTED", "Initial state in the <b>source frame</b>"),
            ("ENTRY", "Trigger condition <i>flag = on</i> observed"),
            ("EXIT", "Handoff command issued"),
            ("NOTE", "Covers init, dwell, and the opening handshake"),
        ],
    ),
    Phase(
        "p2",
        "Phase 2 - Transform",
        "#d79b00",
        "#d79b00",
        "#fff2e0",
        "#7a5300",
        rows=[
            ("REPORTED", "Chained transform <i>src -> mid -> dest</i>"),
            ("ENTRY", "Handoff command from Phase 1"),
            ("EXIT", "Waypoint reached (position + speed)"),
            ("NOTE", "Self-report still arrives in the source frame"),
        ],
    ),
    Phase(
        "p3",
        "Phase 3 - Hold + Recover",
        "#9673a6",
        "#9673a6",
        "#f1ebf4",
        "#5e4570",
        rows=[
            ("REPORTED", "Last transformed pose, <b>frozen</b>"),
            ("ENTRY", "Waypoint reached (Phase 2 exit)"),
            ("EXIT", "Re-localisation detected"),
            ("NOTE", "Lane A reports while Lane B recovers in background"),
        ],
    ),
]

TITLE_TEXT = "Three-phase state management across a handoff"
CAPTION_TEXT = (
    "Phases run sequentially <b>P1 -> P2 -> P3</b>; one report is delivered "
    "every cycle in <b>every phase</b>."
)
FOOTER_TEXT = (
    "<i>italic</i> = field/variable name; identifiers vary by embodiment."
)


def emit_phase_column(page: Page, phase: Phase, x: int, y: int) -> int:
    row_hs = [row_height(body) for _, body in phase.rows]
    rows_total = sum(row_hs) + ROW_GAP * (len(row_hs) - 1)
    col_total = PHASE_HEADER_H + rows_total + 8

    page.add(
        cell(
            f"{phase.pid}_frame",
            "",
            f"rounded=2;whiteSpace=wrap;html=1;fillColor=none;"
            f"strokeColor={phase.border};strokeWidth=2;",
            x,
            y,
            COL_W,
            col_total,
        )
    )
    page.add(
        cell(
            f"{phase.pid}_hdr",
            phase.name,
            f"rounded=0;whiteSpace=wrap;html=1;fillColor={phase.header_fill};"
            f"strokeColor={phase.header_fill};align=center;verticalAlign=middle;"
            f"fontStyle=1;fontSize={FS_PHASE_HEADER};fontColor=#ffffff;letterSpacing=1;",
            x,
            y,
            COL_W,
            PHASE_HEADER_H,
        )
    )

    row_y = y + PHASE_HEADER_H + 4
    for (label, body), rh in zip(phase.rows, row_hs):
        page.add(
            cell(
                f"{phase.pid}_{label.lower()}_box",
                "",
                f"rounded=1;whiteSpace=wrap;html=1;fillColor={phase.body_fill};"
                f"strokeColor={phase.border};strokeWidth=1;",
                x + 4,
                row_y,
                COL_W - 8,
                rh,
            )
        )
        page.add(
            cell(
                f"{phase.pid}_{label.lower()}_lbl",
                label,
                f"text;html=1;fontSize={FS_LABEL};fontStyle=1;"
                f"fontColor={phase.label_color};align=left;verticalAlign=top;"
                f"letterSpacing=2;",
                x + 12,
                row_y + 4,
                COL_W - 24,
                14,
            )
        )
        page.add(
            cell(
                f"{phase.pid}_{label.lower()}_txt",
                body,
                f"text;html=1;align=left;verticalAlign=middle;spacingLeft={COL_PAD_LR};"
                f"spacingRight={COL_PAD_LR};fontSize={FS_BODY};fontColor=#1f1f1f;"
                f"whiteSpace=wrap;",
                x + 4,
                row_y + ROW_LABEL_OFFSET,
                COL_W - 8,
                rh - ROW_LABEL_OFFSET,
            )
        )
        row_y += rh + ROW_GAP

    return col_total


def main() -> None:
    page = Page(PAGE_W, PAGE_H, name="Three-phase strip", diagram_id="phasestrip")
    y = TOP_MARGIN

    page.add(
        cell(
            "title",
            TITLE_TEXT,
            f"text;html=1;fontSize={FS_TITLE};fontStyle=1;fontColor=#1f1f1f;"
            f"align=center;verticalAlign=middle;whiteSpace=wrap;",
            MARGIN_X,
            y,
            PAGE_W - 2 * MARGIN_X,
            TITLE_H,
        )
    )
    y += TITLE_H + 4

    cap_h = max(
        CAPTION_MIN_H,
        text_block_height(CAPTION_TEXT, FS_CAPTION, PAGE_W - 2 * MARGIN_X - 20, 4, 4),
    )
    page.add(
        cell(
            "caption",
            CAPTION_TEXT,
            f"text;html=1;fontSize={FS_CAPTION};fontColor=#444444;align=center;"
            f"verticalAlign=middle;whiteSpace=wrap;",
            MARGIN_X,
            y,
            PAGE_W - 2 * MARGIN_X,
            cap_h,
        )
    )
    y += cap_h + 10

    col_xs = [MARGIN_X + i * (COL_W + COL_GAP) for i in range(N_COLS)]
    strip_top_y = y
    col_hs = [emit_phase_column(page, ph, cx, y) for ph, cx in zip(PHASES, col_xs)]
    y = strip_top_y + max(col_hs)

    arrow_y = strip_top_y + PHASE_HEADER_H // 2
    for i in range(N_COLS - 1):
        page.add(
            arrow_cell(
                f"transition_{i+1}",
                col_xs[i] + COL_W + 1,
                arrow_y,
                col_xs[i + 1] - 1,
                arrow_y,
                "#555555",
                width=2.0,
            )
        )
    y += 14

    footer_h = max(
        FOOTER_MIN_H,
        text_block_height(FOOTER_TEXT, FS_FOOTER, PAGE_W - 2 * MARGIN_X - 20, 4, 4),
    )
    page.add(
        cell(
            "footer",
            FOOTER_TEXT,
            f"text;html=1;align=center;verticalAlign=middle;fontSize={FS_FOOTER};"
            f"fontStyle=2;fontColor=#666666;whiteSpace=wrap;",
            MARGIN_X,
            y,
            PAGE_W - 2 * MARGIN_X,
            footer_h,
        )
    )
    y_final = y + footer_h

    out = Path(__file__).parent / "three_phase_strip.drawio"
    out.write_text(page.render(y_final))
    print(f"Wrote {out} (content reaches y={y_final}, page height={PAGE_H})")


if __name__ == "__main__":
    main()
