#!/bin/bash
# claude-remote-launch.sh  (macOS supervisor for the resilient-host skill)
#
# Run a `claude --remote-control` session inside a dedicated tmux PTY and keep
# it supervised. Designed to be the ProgramArguments target of the LaunchAgent
# com.__USER__.claude-remote (RunAtLoad + KeepAlive): it starts Claude in a
# detached tmux server, then BLOCKS while that session is alive. When Claude
# exits/crashes the session dies, this script exits, and launchd relaunches it.
#
# tmux is REQUIRED: `claude --remote-control` needs a real PTY or it falls back
# to --print mode and won't start an interactive session. `brew install tmux`.
#
# Edit LABEL / WORKDIR below. tmux/claude/curl are resolved from PATH (set in
# the plist) so this works on both Apple Silicon (/opt/homebrew) and Intel
# (/usr/local) Homebrew layouts.
set -u

LABEL="claude-host"          # name shown in claude.ai / the mobile app
WORKDIR="${HOME}"            # directory Claude starts in
SESSION="main"
SOCK="claude"               # dedicated tmux server: tmux -L claude

TMUX_BIN="$(command -v tmux  || echo /opt/homebrew/bin/tmux)"
CLAUDE="$(command -v claude || echo "${HOME}/.local/bin/claude")"
CURL_BIN="$(command -v curl || echo /usr/bin/curl)"

# 1. Wait (up to ~60s) for the Anthropic API to be reachable before launching,
#    so remote control can register on a fresh login before Wi-Fi is up. Exit
#    non-zero on timeout -> launchd (KeepAlive) retries.
for i in $(seq 1 30); do
  if "$CURL_BIN" -sS -o /dev/null --max-time 5 https://api.anthropic.com 2>/dev/null; then
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "$(date '+%F %T') network not ready after wait; exiting for relaunch" >&2
    exit 1
  fi
  sleep 2
done

# 2. Kill any stale dedicated tmux server, then start Claude in a fresh PTY.
"$TMUX_BIN" -L "$SOCK" kill-server 2>/dev/null || true
echo "$(date '+%F %T') starting claude --remote-control $LABEL in $WORKDIR" >&2
"$TMUX_BIN" -L "$SOCK" new-session -d -s "$SESSION" -c "$WORKDIR" \
  "$CLAUDE --remote-control $LABEL"

# 3. Block while the session lives; exit when it dies so launchd relaunches us.
while "$TMUX_BIN" -L "$SOCK" has-session -t "$SESSION" 2>/dev/null; do
  sleep 5
done
echo "$(date '+%F %T') claude tmux session ended; exiting for relaunch" >&2
exit 0
