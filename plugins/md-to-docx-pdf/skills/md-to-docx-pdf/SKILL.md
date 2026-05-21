---
name: md-to-docx-pdf
description: Use this skill when the user wants to render a Markdown document into a styled, publication-quality DOCX and/or PDF — e.g. "build a PDF from this markdown", "generate the report docx", "turn these .md sections into a formatted document with a title page and tables". It drives a bundled python-docx renderer (title page, inline bold/italic/code, content-weighted auto-width tables, lists, checkboxes, fenced code, embedded images) and converts to PDF via LibreOffice headless. Pairs with figure skills; figures authored elsewhere embed via standard Markdown image syntax.
version: 0.1.0
---

# md-to-docx-pdf — Markdown to styled DOCX + PDF

## Purpose

Turn one or more Markdown files into a styled DOCX (and a PDF via LibreOffice
headless) with a title page, consistent heading styles, content-weighted
auto-width tables, and embedded figures. The renderer is `scripts/md_to_docx_pdf.py`.

This is the "publish" half of an authoring loop: author prose in Markdown, author
figures with a figure skill, then build the deliverable document here. Figures
embed with ordinary `![alt](path)` syntax and are centred at a fixed print width.

## When to use

- The user has Markdown content and wants a formatted `.docx` / `.pdf` out.
- A document needs a title page, styled headings, and compact tables.
- A figure-authoring loop produced PNGs that now need to land in a document.

Do **not** reach for a heavyweight toolchain (pandoc/LaTeX) unless the user asks;
this renderer covers the common report/disclosure case with no system deps beyond
python-docx and LibreOffice.

## Preconditions

- `python-docx` in the active Python env: `pip install python-docx`.
- A `libreoffice` (or `soffice`) binary on PATH for the PDF step. Override with
  `$LIBREOFFICE_BIN`. If absent, the DOCX is still produced and the PDF is skipped
  with a warning.

## Supported Markdown subset

| Element | Notes |
|---|---|
| Headings `#`..`#####` | The **first H1 is consumed by the title page**; body starts after it. H4+ capped at Heading 4. |
| Inline | `**bold**`, `*italic*`, `***bold-italic***`, `` `code` ``. Escapes `\*` and `\\` survive (so `A\*STAR` doesn't italicise). |
| Tables | Pipe tables; column widths computed from content (fixed layout) to minimise height. |
| Lists | Bullet (`-`/`*`), numbered, and checkboxes (`- [ ]` / `- [x]`). Nesting by indent. |
| Code | Fenced ```` ``` ```` blocks, monospaced. |
| Rule | `---` renders a thin horizontal rule. |
| Images | `![alt](path)`, resolved **relative to the Markdown file's directory**, centred at the configured width. Missing images render a visible red placeholder. |

## Usage

**Single document (flags):**
```bash
python3 scripts/md_to_docx_pdf.py INPUT.md [MORE.md ...] \
  --out-docx OUT.docx [--out-pdf OUT.pdf] \
  --title "Title" [--subtitle "Sub"] [--author "Name"] \
  [--institute "Org"] [--date YYYY-MM-DD] [--banner CONFIDENTIAL] \
  [--footer "line one" --footer "line two"]
```
Multiple input files concatenate into one document with a page break between.

**Multiple documents (JSON config)** — build several in one run (e.g. a main
form plus a companion annex), paths relative to the config file:
```bash
python3 scripts/md_to_docx_pdf.py --config build.json
```
```json
{
  "documents": [
    {"inputs": ["report.md"], "out_docx": "report.docx",
     "title": "Report", "subtitle": "...", "author": "...", "banner": "CONFIDENTIAL"},
    {"inputs": ["annex.md"], "out_docx": "annex.docx", "title": "Annex"}
  ]
}
```
Config keys mirror the `DocConfig` dataclass: `inputs`, `out_docx`, `out_pdf`,
`title`, `subtitle`, `author`, `institute`, `date`, `banner`, `footer_lines`,
plus styling overrides (`body_font`, `body_pt`, `heading_color`, page/margin
sizes, `table_width_cm`, `image_width_cm`).

See `examples/example.md` + `examples/build_example.json` for a working build.

## Workflow

1. Confirm inputs, output paths, and title-page fields (title/subtitle/author/
   banner). If the user builds the same document repeatedly, prefer a committed
   JSON config over long flag invocations.
2. Run the renderer. **Always rebuild after any Markdown edit** — the PDF is the
   review artefact; deferring the rebuild creates source/render drift and hides
   figure/layout problems.
3. **Verify the rendered PDF**, don't trust the DOCX preview. Render the relevant
   page(s) and read them back:
   ```bash
   pdfinfo OUT.pdf | grep -E "Pages|Page size"
   pdftotext -layout OUT.pdf - | grep -n "Heading text"   # find the page
   pdftoppm -f <page> -l <page> -png OUT.pdf /tmp/chk       # -png REQUIRED
   ```
   then `Read /tmp/chk-<page>.png`. Check: title page correct, headings styled,
   tables not overflowing the margin, figures centred and legible at print width,
   no broken-image placeholders.

## Anti-patterns

- **Trusting the DOCX preview for layout** — render the PDF and read it; LibreOffice
  re-flows tables and images differently from Word.
- **Editing Markdown and not rebuilding** — always regenerate the PDF in the same turn.
- **Hardcoding column widths** — let the content-weighted layout size tables; only
  override `table_width_cm` for the overall frame.
- **Absolute image paths in Markdown** — keep images relative to the `.md` so the
  document is portable; the renderer resolves them per source-file directory.
- **Putting figures in the wrong source file** — if a document is split across
  inputs (e.g. a form vs a companion description), place each figure in the file
  whose directory holds the PNG it references.
