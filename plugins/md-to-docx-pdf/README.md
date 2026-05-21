# md-to-docx-pdf

Render Markdown into a **styled DOCX and PDF** (PDF via LibreOffice headless),
with a title page, content-weighted auto-width tables, and embedded figures.
The "publish" half of an authoring loop: write prose in Markdown, author figures
with a figure skill, then build the deliverable here.

## What's in the box

| Path | What it is |
|---|---|
| `skills/md-to-docx-pdf/SKILL.md` | The skill: supported Markdown subset, usage, and the build → verify-PDF workflow. |
| `scripts/md_to_docx_pdf.py` | The renderer + CLI (single-document flags or multi-document JSON config). |
| `examples/example.md` + `examples/build_example.json` | A working build covering every supported element. |

## Features

- Title page (banner, title, subtitle, author/institute/date or custom footer lines).
- Headings `#`..`#####` (first H1 consumed by the title page; capped at Heading 4).
- Inline `**bold**`, `*italic*`, `***bold-italic***`, `` `code` ``, with `\*` / `\\` escapes.
- Pipe tables with **content-weighted fixed column widths** to minimise table height.
- Bullet / numbered / checkbox lists with indent nesting.
- Fenced code blocks, horizontal rules.
- Embedded images (`![alt](path)`, resolved relative to the Markdown file, centred).
- Single-document (flags) or multi-document (JSON config) builds in one run.

## Setup

```
/plugin install md-to-docx-pdf@claude-skills
pip install python-docx
# plus a LibreOffice install providing `libreoffice` or `soffice` on PATH
# (set $LIBREOFFICE_BIN to override). Without it, the DOCX still builds; PDF is skipped.
```

## Usage

```bash
# Single document:
python3 plugins/md-to-docx-pdf/scripts/md_to_docx_pdf.py report.md \
  --out-docx report.docx --title "Report" --subtitle "Q3" \
  --author "Jane Doe" --banner CONFIDENTIAL

# Multiple documents (paths relative to the config file):
python3 plugins/md-to-docx-pdf/scripts/md_to_docx_pdf.py --config build.json

# Try the bundled example:
python3 plugins/md-to-docx-pdf/scripts/md_to_docx_pdf.py \
  --config plugins/md-to-docx-pdf/examples/build_example.json
```

## Verify the output

LibreOffice re-flows tables and images differently from Word, so check the
**rendered PDF**, not the DOCX preview:

```bash
pdftotext -layout report.pdf - | grep -n "Some heading"   # find the page
pdftoppm -f <page> -l <page> -png report.pdf /tmp/chk       # -png REQUIRED
# then read /tmp/chk-<page>.png
```

## Pairs with

[`drawio-figure-iterate`](../drawio-figure-iterate/) — author print-legible
figures, then embed their PNGs here with standard Markdown image syntax.

## License

MIT. See the repository `LICENSE`.
