#!/bin/sh
# Claude Code status line (up to 4 lines, dashboard layout for easy glance):
#   Line 1: model · cwd
#   Line 2: git — upstream repo (owner/group/name) · branch
#   Line 3: context window  — labeled progress bar + token counts
#   Line 4: usage — subscription rate-limit windows (5h & 7d), OR, for
#           enterprise/API/cloud billing, "session cost $X · duration Y".
#
# All segments degrade gracefully: a field absent from the stdin payload is
# omitted, and its line is dropped. `rate_limits` only appears for claude.ai
# subscription auth (Pro/Max/Team) and only once the CLI has seen rate-limit
# headers from an API response — so on subscription it may be absent on a fresh
# session's first render, then populate. Enterprise/API-key/Bedrock/Vertex/
# Foundry billing never reports it; line 4 instead shows the session cost +
# wall-clock duration, prefixed with the billing mode when an env var names it
# (api/bedrock/vertex/foundry/gateway) and bare otherwise (claude.ai enterprise).
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
# Helper: humanize a millisecond duration -> "1h9m" / "12m34s" / "45s".
# Prints nothing for empty / non-integer / zero input.
# ---------------------------------------------------------------------------
fmt_dur() {
  ms="$1"
  case "$ms" in ''|*[!0-9]*) return 0 ;; esac
  s=$(( ms / 1000 ))
  [ "$s" -gt 0 ] 2>/dev/null || return 0
  h=$(( s / 3600 )); m=$(( (s % 3600) / 60 )); sec=$(( s % 60 ))
  if   [ "$h" -gt 0 ]; then printf "%dh%dm" "$h" "$m"
  elif [ "$m" -gt 0 ]; then printf "%dm%ds" "$m" "$sec"
  else                      printf "%ds" "$sec"
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
# Line 4: usage — subscription windows OR enterprise/API billing mode + cost
#
# The payload carries no billing-mode field. `rate_limits` is present only for
# claude.ai subscription auth (Pro/Max/Team) and only after the first API
# response; every other mode (API key, Bedrock, Vertex, Foundry, gateway) never
# reports it. So:
#   - rate_limits present  -> render whichever of the 5h/7d windows exist.
#   - rate_limits absent, but a non-subscription auth env var is set
#                          -> render "<mode>  session cost $X · duration Y".
#   - rate_limits absent, no env var, but cost > 0
#                          -> render the bare "session cost $X · duration Y"
#                             (steady-state claude.ai enterprise: a positive cost
#                             with no windows can only be a non-subscription mode).
#   - rate_limits absent, no env var, cost 0
#                          -> render nothing (a subscription session whose windows
#                             have not populated yet — stay silent, don't mislabel).
# Mode is detected from environment the CLI exports to this subprocess.
# CLAUDE_CODE_OAUTH_TOKEN is deliberately NOT a signal: it is a subscription
# token (from `claude setup-token`) and still reports rate_limits.
# ---------------------------------------------------------------------------
win_segment=""
fh_pct=$(echo "$input"   | jq -r '.rate_limits.five_hour.used_percentage // empty')
fh_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
sd_pct=$(echo "$input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
sd_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

if [ -n "$fh_pct" ] || [ -n "$sd_pct" ]; then
  # Subscription: render whichever windows are present.
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
else
  # No subscription windows — identify a non-subscription billing mode from env.
  # Only these mean "windows will never come"; absent all of them we stay silent.
  mode=""
  if   [ -n "$CLAUDE_CODE_USE_BEDROCK" ]; then mode="bedrock"
  elif [ -n "$CLAUDE_CODE_USE_VERTEX" ];  then mode="vertex"
  elif [ -n "$CLAUDE_CODE_USE_FOUNDRY" ]; then mode="foundry"
  elif [ -n "$ANTHROPIC_API_KEY" ];       then mode="api"
  elif [ -n "$ANTHROPIC_AUTH_TOKEN" ] || [ -n "$ANTHROPIC_BASE_URL" ]; then mode="gateway"
  fi
  cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
  cost_pos=$([ -n "$cost" ] && awk -v c="$cost" 'BEGIN{ if (c+0 > 0) print 1 }')
  # Build a "session cost $X · duration Y" detail from the payload's cost block
  # (a /cost-style readout — both fields are CLI-computed, so the total is
  # authoritative; we don't recompute it). Per-model breakdown is NOT in the
  # payload, so it's intentionally out of scope here.
  cost_detail=""
  if [ -n "$cost_pos" ]; then
    cost_detail="session cost \$$(printf '%.2f' "$cost")"
    d=$(fmt_dur "$(echo "$input" | jq -r '.cost.total_duration_ms // empty')")
    [ -n "$d" ] && cost_detail="$cost_detail · duration $d"
  fi
  if [ -n "$mode" ]; then
    # Explicit non-subscription env signal: label the mode, append cost detail.
    win_segment="$mode"
    [ -n "$cost_detail" ] && win_segment="$win_segment  $cost_detail"
  elif [ -n "$cost_detail" ]; then
    # No windows and no env signal, yet cost > 0. A subscription session with
    # API activity would have populated rate_limits, and a fresh one has cost 0
    # — so cost > 0 here means a non-subscription mode that exposes no env var
    # (notably claude.ai *enterprise*). Show the cost detail so line 4 isn't
    # blank. Bare (no mode word) since we can't name the billing path.
    win_segment="$cost_detail"
  fi
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

# Always succeed: a non-zero exit (e.g. the last test above being false when
# line 4 is empty) can make Claude Code suppress the rendered status line.
exit 0
