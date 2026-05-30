---
name: cc-statusline
description: Install or port a 4-line Claude Code status line dashboard — line 1 model + cwd, line 2 the upstream git repo + branch, line 3 a context-window progress bar with token counts, line 4 the 5-hour & 7-day subscription rate-limit usage with reset countdowns. Use when the user wants to set up, copy to another machine, troubleshoot, or customize their Claude Code statusLine.
---

# Status line dashboard

A multi-line Claude Code `statusLine` that reads everything from the JSON the CLI
pipes to the status-line command on stdin — no external services, no polling.

Rendered output:

```
Opus 4.8  ~/ws/edh_decks
hanifz-dr1/iron_td_drafts ⎇ main
ctx [██████░░░░░░░░] 43%   85k/1M
5h:43% (resets 2h41m)   7d:18% (resets 4d3h)
```

- **Line 1** — model display name + cwd (home shortened to `~`).
- **Line 2** — git context: the upstream remote's repo path
  (`<owner/group>/<repo>`) + branch as `⎇ <branch>`. Detached HEAD shows
  `⎇ <short-sha>`; a repo with no remote drops the path and shows just
  `⎇ <branch>`; outside any repo the line reads `⎇ no git`.
- **Line 3** — context window as a 14-cell progress bar + compact token counts
  (`85k/1M`, `156k/200k`).
- **Line 4** — the two subscription rate-limit windows from `/usage`: the
  5-hour rolling window and the 7-day (weekly) window, each as `% used` plus a
  countdown to reset.

Every segment degrades gracefully: any field missing from the payload is
omitted, and an empty line is dropped (a fresh session with no rate-limit data
yet renders without the rate-limit line, then fills it in after the first API
response).

## How it works — the statusLine contract

Claude Code invokes the configured command on each render and pipes a JSON
object to **stdin**. The script parses it with `jq`. The fields this dashboard
relies on (verified against the CLI's payload constructor, Claude Code 2.1.156):

```jsonc
{
  "model":     { "id": "...", "display_name": "Opus 4.8" },
  "workspace": { "current_dir": "/abs/path", "project_dir": "..." },
  "cwd": "/abs/path",                        // fallback for current_dir
  "context_window": {
    "used_percentage": 43.0,                 // 0-100
    "total_input_tokens": 85300,
    "context_window_size": 1000000
  },
  "rate_limits": {                           // ONLY present after the session
    "five_hour": {                           // has seen >=1 API response, and
      "used_percentage": 43.2,               // only on plans that report
      "resets_at": 1779993058                // unified rate limits (Pro/Max).
    },                                        // resets_at is epoch SECONDS.
    "seven_day": { "used_percentage": 17.8, "resets_at": 1780320000 }
  },
  "cost": { "total_cost_usd": 0.74, "total_lines_added": 128, ... },  // unused here
  "exceeds_200k_tokens": false
}
```

Key facts that are easy to get wrong:

- **`rate_limits` is conditional.** The CLI only adds it when it has rate-limit
  state from at least one API response this session (constructor gate:
  `(v.five_hour || v.seven_day) && { rate_limits: v }`). So line 3 is legitimately
  absent on a brand-new session's first render, and absent entirely on raw
  API-key billing (no subscription windows). This is NOT a bug — don't try to
  source it from the transcript JSONL; the windows are not logged there.
- **`used_percentage` is already 0-100** (the CLI computes `utilization * 100`).
- **`resets_at` is epoch seconds.** The script also accepts ISO-8601 defensively.
- This data is the same on macOS and Linux and across models — it's part of the
  statusLine payload, not OS- or model-specific. There is nothing extra to
  install to "unlock" it.

## Prerequisites

POSIX `sh` plus: `jq`, `awk`, `date`, `sed`, and `git` (for line 2). All ship by
default on macOS and typical Linux. (`bc` is **not** needed.) The reset-time
formatter handles both GNU `date -d` (Linux) and BSD `date -j -f` (macOS)
automatically. If `git` is absent the git line simply reads `⎇ no git`; the rest
is unaffected.

## Install (idempotent — preserves existing settings)

Run these on the target machine. They copy the bundled script into place and
merge the `statusLine` key into `~/.claude/settings.json` without clobbering
anything else.

```sh
# 1. Install the script (this skill folder ships statusline-command.sh).
#    If invoked as a skill, copy the adjacent file; otherwise recreate it
#    from the "Reference script" block below.
mkdir -p ~/.claude
cp "<this-skill-dir>/statusline-command.sh" ~/.claude/statusline-command.sh
chmod +x ~/.claude/statusline-command.sh

# 2. Wire it into settings.json (creates the file if absent, preserves the rest).
[ -f ~/.claude/settings.json ] || echo '{}' > ~/.claude/settings.json
tmp=$(mktemp)
jq --arg cmd "bash $HOME/.claude/statusline-command.sh" \
   '.statusLine = {type:"command", command:$cmd}' \
   ~/.claude/settings.json > "$tmp" && mv "$tmp" ~/.claude/settings.json

# 3. Verify (see "Verify" below). The live status line refreshes on the next
#    render — no restart required.
```

When running this as a skill, `<this-skill-dir>` is this skill's own directory
(the folder containing this SKILL.md). If the bundled script can't be located,
recreate `~/.claude/statusline-command.sh` verbatim from the Reference script
block at the bottom of this file, then `chmod +x` it.

## Verify

Feed the script synthetic payloads and confirm the layouts. `resets_at` here is
computed relative to now so the countdown is non-trivial. Point `current_dir` at
a real git checkout to see the repo/branch line populate (or a non-repo path to
see `⎇ no git`):

```sh
SH=~/.claude/statusline-command.sh
NOW=$(date +%s); FH=$((NOW + 9660)); SD=$((NOW + 360000))

# Full dashboard — run from inside a git repo to populate line 2
printf '{"model":{"display_name":"Opus 4.8"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":43,"total_input_tokens":85300,"context_window_size":1000000},"rate_limits":{"five_hour":{"used_percentage":43.2,"resets_at":%s},"seven_day":{"used_percentage":17.8,"resets_at":%s}}}' "$PWD" "$FH" "$SD" | sh "$SH"; echo

# Fresh session (no rate_limits), non-repo dir -> model/cwd, "⎇ no git", ctx
printf '{"model":{"display_name":"Opus 4.8"},"cwd":"%s","context_window":{"used_percentage":4,"total_input_tokens":8000,"context_window_size":1000000}}' "/tmp" | sh "$SH"; echo
```

Expected: the first prints 4 lines (model/cwd, `<repo> ⎇ <branch>`,
`ctx [...] 43% 85k/1M`, `5h:43% (resets …)   7d:18% (resets …)`); the second
prints 3 lines, with `⎇ no git` for the git line and no rate-limit line.

## Troubleshooting

- **Rate-limit line never appears.** Expected on a fresh session until the first
  API response; expected permanently on raw API-key usage (no subscription
  windows). Confirm with the "Full dashboard" verify payload — if that renders
  the rate-limit line, the script is fine and the live session simply has no
  `rate_limits` field yet.
- **Git line shows `⎇ no git` inside a real repo.** The dir passed in the payload
  isn't a git work tree from the script's view, or `git` isn't on `PATH`. Check
  `git -C "<dir>" rev-parse --abbrev-ref HEAD`.
- **Repo path missing but branch shows.** The repo has no upstream/`origin`
  remote (or no remotes at all); the script drops the path and shows just
  `⎇ <branch>`. Add a remote to populate `<owner/group>/<repo>`.
- **No status line at all / shows a shell error.** Check `jq` is installed and
  that `~/.claude/settings.json` is valid JSON (`jq . ~/.claude/settings.json`).
  Re-run the verify payloads to isolate script vs. config.
- **Reset countdown missing but percent shows.** `resets_at` was unparseable or
  already in the past; the script intentionally omits the `(resets …)` clause
  then. Real epoch-seconds values always work.
- **Countdown looks ~1 minute low.** It floors to the minute, and a few seconds
  of script runtime elapse — cosmetic only.
- **`~` not expanded in the command.** The install uses an absolute `$HOME` path
  in `settings.json`, so this won't happen if you used the snippet above.

## Customization

- **Bar width**: change the `14` passed to `make_bar` on the context line.
- **Git line format**: line 2 is `branch_segment` (`<repo> ⎇ <branch>`). Swap the
  order, change the `⎇` glyph, or drop the repo path by editing the
  `branch_segment=` assignments. The `no git` text for non-repos is set in the
  same block.
- **Different model info on line 1**: line 1 is just `model` + `cwd`; extend
  `line1` to add more.
- **Re-add session cost**: the payload's `cost.total_cost_usd`,
  `cost.total_lines_added/removed`, `cost.total_duration_ms` are available; a
  prior version rendered `$0.74 +128/-34 12m34s`. Add another line if wanted.
  (Note: that's API/usage *cost*, distinct from the rate-limit *windows*.)
- **Collapse to fewer lines**: concatenate
  `line1`/`branch_segment`/`ctx_segment`/`win_segment` with two spaces instead of
  `\n` at the bottom of the script.

## Reference script

Canonical copy lives beside this file as `statusline-command.sh` (what the
install step copies). This block mirrors it for reconstruction if the bundled
file is unavailable — keep the two in sync.

```sh
#!/bin/sh
# Claude Code status line (up to 4 lines, dashboard layout for easy glance):
#   Line 1: model · cwd
#   Line 2: git — upstream repo (owner/group/name) · branch
#   Line 3: context window  — labeled progress bar + token counts
#   Line 4: rate-limit windows — 5-hour & 7-day (% used + reset countdown)
#
# All segments degrade gracefully: a field absent from the stdin payload is
# omitted, and its line is dropped. `rate_limits` only appears once the CLI
# has seen rate-limit headers from an API response, so the rate-limit line may
# be absent on a fresh session's first render, then populate.
input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Claude"')
cwd_raw=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
# Shorten home directory to ~
cwd=$(echo "$cwd_raw" | sed "s|^$HOME|~|")

# Git branch + upstream repo for the current working directory.
#   In a repo  -> "<owner/group>/<repo> ⎇ <branch>"
#                 (⎇ <short-sha> on a detached HEAD; repo prefix dropped if no remote).
#   Not a repo -> "⎇ no git".
# The repo path is parsed from the upstream remote's URL — SSH (git@host:owner/repo.git),
# HTTPS (https://host/owner/repo.git), and nested groups (gitlab.com/grp/sub/repo) all map
# to the full namespace path with host and trailing .git stripped.
branch_segment=""
if [ -n "$cwd_raw" ]; then
  if br=$(git -C "$cwd_raw" rev-parse --abbrev-ref HEAD 2>/dev/null); then
    [ "$br" = "HEAD" ] && br=$(git -C "$cwd_raw" rev-parse --short HEAD 2>/dev/null)
    # Remote backing the current branch's upstream, else origin, else the first remote.
    remote=$(git -C "$cwd_raw" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null | sed 's#/.*##')
    [ -n "$remote" ] || remote="origin"
    git -C "$cwd_raw" remote get-url "$remote" >/dev/null 2>&1 || remote=$(git -C "$cwd_raw" remote 2>/dev/null | head -n1)
    repo=""
    if [ -n "$remote" ]; then
      url=$(git -C "$cwd_raw" remote get-url "$remote" 2>/dev/null)
      repo=$(echo "$url" | sed -E 's#^[a-z]+://[^/]+/##; s#^[^@]*@[^:/]+[:/]##; s#\.git$##')
    fi
    [ -n "$repo" ] && branch_segment="$repo ⎇ $br" || branch_segment="⎇ $br"
  else
    branch_segment="⎇ no git"
  fi
fi

# ---------------------------------------------------------------------------
# Helper: render a [████░░░░] progress bar for a 0-100 percentage.
#   $1 = percent, $2 = width (default 14)
# ---------------------------------------------------------------------------
make_bar() {
  awk -v p="$1" -v w="${2:-14}" 'BEGIN{
    if (p < 0) p = 0; if (p > 100) p = 100;
    n = int(p * w / 100 + 0.5);
    out = "";
    for (i = 0; i < n; i++) out = out "█";
    for (i = n; i < w; i++) out = out "░";
    printf "%s", out;
  }'
}

# ---------------------------------------------------------------------------
# Helper: format a token count compactly — 85000 -> "85k", 1000000 -> "1M".
# ---------------------------------------------------------------------------
fmt_tokens() {
  awk -v n="$1" 'BEGIN{
    if (n >= 1000000) { v = n / 1000000; printf (v == int(v) ? "%dM" : "%.1fM"), v }
    else             { printf "%dk", int(n / 1000 + 0.5) }
  }'
}

# ---------------------------------------------------------------------------
# Helper: humanize a reset timestamp into "1h23m" / "3d4h" / "45m".
# Accepts epoch seconds OR ISO-8601 (UTC). Prints nothing if past/unparseable.
# ---------------------------------------------------------------------------
fmt_reset() {
  ra="$1"
  [ -n "$ra" ] || return 0
  now=$(date +%s)
  case "$ra" in
    ''|*[!0-9]*)
      target=$(date -d "$ra" +%s 2>/dev/null) \
        || target=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${ra%%[+.Z]*}" +%s 2>/dev/null)
      ;;
    *) target="$ra" ;;
  esac
  [ -n "$target" ] || return 0
  delta=$(( target - now ))
  # Sanity guard: windows are <=7d; a huge delta means resets_at was in ms.
  [ "$delta" -gt 2592000 ] 2>/dev/null && delta=$(( (target / 1000) - now ))
  [ "$delta" -gt 0 ] 2>/dev/null || return 0
  d=$(( delta / 86400 )); h=$(( (delta % 86400) / 3600 )); m=$(( (delta % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf "%dd%dh" "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf "%dh%dm" "$h" "$m"
  else                      printf "%dm" "$m"
  fi
}

# ---------------------------------------------------------------------------
# Line 3: context window
# ---------------------------------------------------------------------------
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // empty')

ctx_segment=""
if [ -n "$used_pct" ]; then
  used_pct_fmt=$(printf "%.0f" "$used_pct")
  bar=$(make_bar "$used_pct" 14)
  ctx_segment="ctx [$bar] ${used_pct_fmt}%"
  if [ -n "$total_input" ] && [ -n "$ctx_size" ]; then
    ctx_segment="$ctx_segment   $(fmt_tokens "$total_input")/$(fmt_tokens "$ctx_size")"
  fi
fi

# ---------------------------------------------------------------------------
# Line 4: rate-limit windows (5h / 7d)
# ---------------------------------------------------------------------------
win_segment=""
fh_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
sd_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
sd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$fh_pct" ]; then
  seg="5h:$(printf '%.0f' "$fh_pct")%"
  r=$(fmt_reset "$fh_reset"); [ -n "$r" ] && seg="$seg (resets $r)"
  win_segment="$seg"
fi
if [ -n "$sd_pct" ]; then
  seg="7d:$(printf '%.0f' "$sd_pct")%"
  r=$(fmt_reset "$sd_reset"); [ -n "$r" ] && seg="$seg (resets $r)"
  [ -n "$win_segment" ] && win_segment="$win_segment   $seg" || win_segment="$seg"
fi

# ---------------------------------------------------------------------------
# Assemble (up to four lines; empty lines dropped)
# ---------------------------------------------------------------------------
line1=""
[ -n "$model" ] && line1="$model"
[ -n "$cwd" ]   && line1="$line1  $cwd"

printf "%s" "$line1"
[ -n "$branch_segment" ] && printf "\n%s" "$branch_segment"
[ -n "$ctx_segment" ] && printf "\n%s" "$ctx_segment"
[ -n "$win_segment" ] && printf "\n%s" "$win_segment"
```
