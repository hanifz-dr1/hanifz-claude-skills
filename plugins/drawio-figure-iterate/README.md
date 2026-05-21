# drawio-figure-iterate

Author **print-legible** draw.io figures with Claude Code through a tight
feedback loop: generate mxGraph XML → export a PNG headlessly → read the PNG
back → score it against a persisted requirements doc → apply targeted fixes →
repeat. For dense, text-heavy figures it drives a PIL-metrics generator so a
label edit can never silently overflow its box.

## What's in the box

| Path | What it is |
|---|---|
| `skills/drawio-figure-iterate/SKILL.md` | The skill: the generate → export → score → fix loop and its rubric. |
| `scripts/export_png.sh` | Cross-platform headless PNG export wrapper (Linux extracted AppImage / macOS bundle / PATH). |
| `scripts/install_exporter_linux.sh` | One-shot setup of the headless exporter on Linux without admin/FUSE. |
| `scripts/figure_generator.py` | Reusable PIL-metrics primitives (measured wrapping, chip sizing, XML emission, page-overflow guard) + a runnable demo. |
| `examples/three_phase_strip.py` | Worked multi-chip generator using the primitives. |
| `.mcp.json` | Optional draw.io MCP server (`@drawio/mcp`) for opening diagrams in the browser to eyeball them. |

## What actually does the work (MCP vs plugin vs CLI)

This is the part people get wrong, so it's stated plainly:

- The **headless draw.io Desktop CLI** is the export engine. Scoring depends on
  it. It is **not** the MCP and **not** any third-party plugin.
- The **draw.io MCP** (`@drawio/mcp`, wired in `.mcp.json`) is **optional** and
  only *opens* a diagram in the browser for human inspection. It does not export
  or edit. The loop runs fine without it.
- The **skill** is the brain (the loop + rubric). The **PIL generator** is the
  hands for dense figures.

So: install this plugin for the skill + scripts + optional MCP. The export still
needs a draw.io binary on the machine (next section).

## Setup

### 1. Install the plugin (provides the skill + optional MCP)

```
/plugin marketplace add <your-github-user>/claude-skills
/plugin install drawio-figure-iterate@claude-skills
```

Installing wires the optional `drawio` MCP server (`npx -y @drawio/mcp`, needs
Node 20+). If you don't want browser-inspection, you can ignore it.

### 2. Provide a headless draw.io binary (required for export)

**Linux (no admin / no FUSE):**
```bash
plugins/drawio-figure-iterate/scripts/install_exporter_linux.sh
```
Extracts a draw.io Desktop AppImage to `~/bin/drawio-desktop/squashfs-root`,
which `export_png.sh` finds automatically.

**macOS:** install draw.io Desktop; `export_png.sh` finds the app bundle.

**Windows / custom path:** set `DRAWIO_BIN` to the executable, or put `drawio` /
`draw.io.exe` on PATH.

### 3. (Optional) Pillow, only if you use the generator

```bash
pip install Pillow
```

## Usage flow

1. Ask Claude to *iterate on* or *auto-refine* a draw.io figure (this triggers
   the skill). Give it: the content/vocabulary that must appear, the layout, the
   medium (e.g. "16 cm wide in a PDF"), and where to write the files.
2. The skill writes/updates `<slug>.md` (the requirements doc — the scoring
   source of truth), authors `<slug>.drawio`, and exports `<slug>.png`.
3. It reads the PNG back and scores it against the rubric (content, vocabulary,
   legibility, layout, visual coherence, formatting), then applies targeted
   fixes and re-exports — up to N iterations (default 3), stopping early once all
   axes pass.
4. If the figure is embedded in a PDF, the final check renders the *embedded
   page* with `pdftoppm` and reads that, because a standalone-clean PNG can still
   be illegible once scaled to print width.
5. You get the final `.drawio` + `.png` (+ the `.md` requirements doc).

### Driving the scripts directly

```bash
# Reusable generator demo (writes a .drawio next to the script):
python3 plugins/drawio-figure-iterate/scripts/figure_generator.py

# Worked multi-chip example:
python3 plugins/drawio-figure-iterate/examples/three_phase_strip.py

# Export any .drawio to PNG at print scale (2 = print quality, 3 = dense):
plugins/drawio-figure-iterate/scripts/export_png.sh some.drawio out.png 2
```

## Design rules baked into the skill

- A4 portrait for print (`pageWidth≈820`); title ≥20 pt, body ≥13 pt at scale 2.
- One fill colour per category, reused by exact hex.
- Escape `< > & "` inside XML attribute values, else drawio drops the model body.
- Chip heights are *measured* (PIL), not guessed; overflow fails the build.
- Score legibility on the rendered raster every iteration — never trust the editor view.

## License

MIT. See the repository `LICENSE`.
