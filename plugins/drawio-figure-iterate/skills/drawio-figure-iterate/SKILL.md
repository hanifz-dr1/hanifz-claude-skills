---
name: drawio-figure-iterate
description: Use this skill when the user asks to auto-generate or auto-improve a draw.io figure through multiple feedback iterations — e.g. "iterate on this diagram", "auto-refine a drawio figure until it's print-legible", "generate a diagram for X with N iterations". Runs a generate -> export -> read-back -> score -> fix loop using a headless draw.io exporter, scoring each iteration against a persisted requirements doc. For dense multi-chip figures it drives a PIL-metrics generator so text can't silently overflow. Returns the final .drawio + .png.
version: 0.1.0
---

# drawio-figure-iterate — feedback loop for print-legible draw.io figures

## Purpose

Produce a draw.io diagram that meets the user's requirements by iterating:
author mxGraph XML -> export PNG headlessly -> read the PNG back and score it ->
diff against requirements -> apply targeted fixes -> repeat until it passes or
the iteration budget is spent.

The non-obvious failure mode this skill exists to prevent: a figure that looks
fine in the editor but is **illegible once scaled to print width** (e.g. 16 cm
in a PDF, ~5 pt body text). The only reliable check is to export at print scale,
read the raster back, and score legibility — every iteration.

## When to drive the PIL generator instead of hand-XML

- **Few boxes, simple flow** -> hand-author the mxGraph XML directly.
- **Many text-bearing chips** (phase tables, comparison matrices, anything where
  a label edit might overflow its box) -> use the bundled
  `scripts/figure_generator.py`. It measures every string with real font metrics,
  computes chip heights instead of guessing, and raises `SystemExit` if the laid
  out page overflows — so an overflow fails the build instead of bleeding off the
  page silently. `examples/three_phase_strip.py` is a worked multi-chip example.

## Inputs (ask the user only if missing)

1. **Requirements spec** — prose + checklist:
   - Content: what nodes/rows/phases/flows must exist; exact vocabulary to preserve.
   - Layout: orientation (LR/TB), grouping, emphasis, page size.
   - Audience/medium: print PDF, slide, web; technical vs executive.

   **Persist requirements in a sibling markdown file** `<slug>.md` next to
   `<slug>.drawio` / `<slug>.png`. This file is the single source of truth used
   when scoring each iteration — read it at the start of every run. When the user
   adds or refines a requirement mid-iteration, update `<slug>.md` in the **same
   turn** as the XML edit so earlier requirements are never silently dropped.
   Append a dated bullet under a `## Change log` heading.

   Suggested sections: Purpose & audience · Content · Canonical vocabulary ·
   Formatting conventions · Layout & size · Visual hygiene (acceptance checks) ·
   Change log.
2. **Max iterations** `N` (default 3; cap at 5 to bound cost).
3. **Output paths**: `<dir>/<slug>.drawio`, `<dir>/<slug>.png`, `<dir>/<slug>.md`.
4. (Optional) **Reference document section** — if the figure supports a written
   doc, locate the canonical wording so labels match verbatim.

## Preconditions

- **Headless exporter.** Use the bundled wrapper:
  ```bash
  scripts/export_png.sh <in>.drawio [<out>.png] [scale]   # scale defaults to 2
  ```
  It resolves the draw.io binary in this order: `$DRAWIO_BIN` -> Linux extracted
  AppImage (`$DRAWIO_APPDIR`, default `~/bin/drawio-desktop/squashfs-root`) ->
  macOS app bundle -> `drawio`/`draw.io` on PATH. On Linux with no admin/FUSE,
  run `scripts/install_exporter_linux.sh` once to extract the AppImage.
  If no binary is available, fall back to opening the `.drawio` in the browser
  editor (drawio MCP) and asking the user to export PNG manually — the scoring
  step still works once the PNG exists.
- **PIL** (`Pillow`) in the active Python env, only if using the generator.
- **drawio MCP** (optional) for opening a diagram in the browser to eyeball it:
  `mcp__drawio__open_drawio_xml`. Fetch via `ToolSearch "select:mcp__drawio__open_drawio_xml"`
  if not loaded. This is a convenience for human inspection, **not** the export
  path — the headless CLI is what scoring depends on.

## Iteration loop

**Before iterating:** read `<slug>.md` (if it exists) and treat every bullet as
a hard constraint. If the user introduced a new requirement this turn, append it
to `<slug>.md` (with a Change-log entry) *first*, then iterate. Never score
against only the freshest feedback — always the full accumulated doc.

For `i` in `1..N`:

1. **Generate** mxGraph XML. Iteration 1 = from-scratch design from the
   requirements (or run the PIL generator). Iteration i>1 = previous XML plus the
   evaluation-derived diff.
2. **Save** to `<slug>.drawio` (wrap in `<mxfile><diagram>…` if not already).
3. **Export PNG** via `scripts/export_png.sh`. If export fails, surface stderr and stop.
4. **Self-evaluate** by reading the PNG with the `Read` tool and scoring against
   this rubric (tight beats vague):

   | Axis | Pass criteria |
   |---|---|
   | **Content coverage** | Every required item is visually present. List missing/extraneous by name. |
   | **Vocabulary fidelity** | Labels match canonical wording verbatim (flag/API names, thresholds). Flag drift. |
   | **Legibility** | No clipping/overflow at export scale. Body text ≥ ~13 pt at scale=2. No text touching a cell's right edge. |
   | **Layout coherence** | No overlaps. Consistent container spacing. Consistent flow direction. Related items grouped. |
   | **Visual coherence** | Colour logic consistent (one fill per category, reuse exact hex). Arrow style consistent. Title/banner/footer rhythm. |
   | **Formatting** | Section headers bold. Code/identifier terms visually distinct from prose. Borders thick enough to group. |

   Emit a short numbered list of concrete fixes (`label X -> Y`, `widen cell Z to
   h=N`, `move arrow A down 30 px`). If all axes pass, **stop early**.
5. **Apply fixes** deterministically — prefer targeted `Edit` over full rewrites
   so working parts stay stable. With the generator, edit the content/constants
   and regenerate.
6. Repeat.

## Print-legibility confirmation (when the figure lands in a PDF)

A standalone-clean PNG can still be unreadable scaled into a document. If the
figure is embedded in a PDF/DOCX at a fixed width, do the final check **inside
the rendered page**, not on the standalone PNG:

```bash
pdftotext -layout doc.pdf - | grep -n "Figure N"      # find the page
pdftoppm -f <page> -l <page> -png doc.pdf /tmp/fig     # -png is REQUIRED
```
then `Read /tmp/fig-<page>.png`. This is the only confirmation of legibility at
true print width.

## After the loop

- Optionally open the final XML via the drawio MCP for the user to inspect.
- Report: iterations used, which axes improved, any residual limitations.
- Do **not** edit the user's prose document unless asked — that's a separate step.

## Anti-patterns

- **Redesigning from scratch each iteration** — you lose what already worked. Edit deltas.
- **Vague self-critique** ("looks cramped") — translate to a numeric fix (`h=170 -> 225`).
- **Growing fonts without growing cells** — the overflow trap. Bump both together,
  or let the generator size the box.
- **Raw `<` / `>` / `&` in an XML attribute value** — drawio silently drops the
  whole `<mxGraphModel>` on import (PNG renders only the title band). Escape to
  entities; the generator's `xml_attr()` does this.
- **Landscape pages for print** — a 1180×720 landscape becomes ~5 pt body at 16 cm.
  Prefer A4 portrait (`pageWidth=820 pageHeight≈1030`), title ≥20 pt, body ≥13 pt.
- **Silent scope creep** — if requirements don't mention colour, don't invent a
  colour system; ask first.
- **>5 iterations** — non-convergence usually means ambiguous requirements. Stop and ask.

## Minimal example (one iteration)

```
Input: "Three-box horizontal flow: Start -> Process -> End, print-legible."
Iter 1: generate XML (3 rounded rects + 2 arrows) -> export PNG -> evaluate:
        boxes ✓, vocab ✓, body 11 pt below target at scale=2 -> bump to 14 pt,
        widen boxes 20 px.
Iter 2: apply fixes -> export + evaluate: all axes pass -> stop.
Return: <slug>.drawio + <slug>.png, 2 iterations.
```
