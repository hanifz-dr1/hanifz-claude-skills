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
| [**cc-statusline**](plugins/cc-statusline/) | Install or port a multi-line Claude Code `statusLine` read entirely from the CLI's stdin JSON: model + cwd, upstream git repo + branch, a context-window progress bar with token counts, and the 5-hour & 7-day rate-limit windows with reset countdowns. Idempotent install; every segment degrades gracefully. |
| [**claude-multi-account**](plugins/claude-multi-account/) | One-time setup of two isolated Claude Code accounts (work + personal) that run simultaneously via per-account `CLAUDE_CONFIG_DIR` shell wrappers. Keeps the existing login on bare `claude` and wraps only the second account so they never race over one credential slot; branches the design when the existing login is the sensitive work account. Self-deletes after verified success. |
| [**resilient-host**](plugins/resilient-host/) | Set up and verify a reboot/power-loss-resilient Claude Code remote-control host in independent layers: a systemd user service running `claude --remote-control` inside a dedicated tmux PTY (`Restart=always` + API pre-check), user linger for no-login boot, SSH, GRUB hidden/zero-timeout, and a BIOS power-on rule. Privileged steps are owner-run sudo blocks. OS/kernel-hang recovery (a hardware watchdog) is intentionally out of scope for now and will be added later. |

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
