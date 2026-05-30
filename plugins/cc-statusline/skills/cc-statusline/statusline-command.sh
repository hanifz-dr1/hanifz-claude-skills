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
