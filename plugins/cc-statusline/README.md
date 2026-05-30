# cc-statusline

A multi-line Claude Code `statusLine` that reads everything from the JSON the CLI
pipes to the status-line command on **stdin** — no external services, no polling.

Rendered output:

```
Opus 4.8  ~/ws/edh_decks
hanifz-dr1/iron_td_drafts ⎇ main
ctx [██████░░░░░░░░] 43%   85k/1M
5h:43% (resets 2h41m)   7d:18% (resets 4d3h)
```

- **Line 1** — model display name + cwd (home shortened to `~`).
- **Line 2** — git context: the upstream remote's repo path (`<owner/group>/<repo>`)
  + branch as `⎇ <branch>`. Detached HEAD shows `⎇ <short-sha>`; a repo with no
  remote drops the path; outside any repo the line reads `⎇ no git`.
- **Line 3** — context window as a 14-cell progress bar + compact token counts.
- **Line 4** — the 5-hour and 7-day subscription rate-limit windows, each as
  `% used` plus a countdown to reset.

Every segment degrades gracefully: any field missing from the payload is omitted,
and its line is dropped.

## What's in the box

| Path | What it is |
|---|---|
| `skills/cc-statusline/SKILL.md` | The install/port/troubleshoot/customize guide and the statusLine payload contract. |
| `skills/cc-statusline/statusline-command.sh` | The canonical status-line script the install step copies to `~/.claude/statusline-command.sh`. |

## Prerequisites

POSIX `sh` plus `jq`, `awk`, `date`, `sed`, and `git` (for the git line). All ship
by default on macOS and typical Linux. If `git` is absent the git line simply
reads `⎇ no git`; the rest is unaffected.

## Setup

```
/plugin install cc-statusline@hanifz-claude-skills
```

Then ask Claude to install the status line, or follow the install snippet in
`SKILL.md` (copies the script into `~/.claude/` and merges the `statusLine` key
into `~/.claude/settings.json` without clobbering anything else).

## License

MIT. See the repository `LICENSE`.
