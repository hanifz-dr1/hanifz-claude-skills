# hanifz-claude-skills

A curated collection of [Claude Code](https://claude.com/claude-code) skills,
packaged as installable plugins. Add the marketplace once, then install
individual skills on demand.

## Install

```
/plugin marketplace add hanifz-dr1/hanifz-claude-skills
```

Then install any skill below:

```
/plugin install <name>@hanifz-claude-skills
```

## Skills in this collection

| Skill | What it does |
|---|---|
| [**drawio-figure-iterate**](plugins/drawio-figure-iterate/) | Author print-legible draw.io figures through a generate → export → read-back → score → fix loop. Bundles a headless PNG exporter, a PIL-metrics generator for overflow-proof multi-chip figures, and an optional draw.io MCP server. |
| [**md-to-docx-pdf**](plugins/md-to-docx-pdf/) | Render Markdown to a styled DOCX + PDF (via LibreOffice headless): title page, inline formatting, content-weighted auto-width tables, lists, code, embedded images. Single- or multi-document builds. Pairs with `drawio-figure-iterate`. |
| [**codex-adversarial-review**](plugins/codex-adversarial-review/) | A two-round methodology for stress-testing prose, claims, or code with an adversarial second model (Codex): brief with attack vectors → synthesise adopt/reject/pushback → re-attack and rule on pushbacks. Requires a Codex MCP/CLI. |

_More skills will be added over time. Each lives under `plugins/<name>/` with its
own `README.md`, `SKILL.md`, and any helper scripts/MCP config._

## Repository layout

```
hanifz-claude-skills/
├── .claude-plugin/
│   └── marketplace.json          # lists every skill/plugin in the collection
└── plugins/
    └── drawio-figure-iterate/    # one curated skill = one plugin
        ├── .claude-plugin/plugin.json
        ├── .mcp.json             # (optional) MCP servers the skill can use
        ├── README.md
        ├── skills/<name>/SKILL.md
        ├── scripts/
        └── examples/
```

## Adding a new skill

1. Create `plugins/<new-skill>/` with `.claude-plugin/plugin.json`, a `README.md`,
   and `skills/<new-skill>/SKILL.md`.
2. Add an entry to `.claude-plugin/marketplace.json` pointing `source` at
   `./plugins/<new-skill>`.
3. Bundle any helper scripts under `plugins/<new-skill>/scripts/` and any MCP
   servers in `plugins/<new-skill>/.mcp.json`.

## License

MIT. See [`LICENSE`](LICENSE).
