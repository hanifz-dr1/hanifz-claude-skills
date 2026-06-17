#!/usr/bin/env bash
# Verify the macOS (launchd) resilient-host setup. Read-only; NO sudo needed for
# the core login-persistence layers. Prints PASS / FAIL / WARN / NOTE per layer.
#
# This is the macOS analog of verify-resilience.sh. It checks the LOGIN-
# PERSISTENCE setup (the common case): a LaunchAgent that starts a
# `claude --remote-control` tmux session every time the owner logs in, and
# relaunches it on crash. The unattended-boot layers (auto-login, FileVault,
# SSH, power-on) are reported as informational because they need sudo and/or a
# security tradeoff -- see SKILL.md "macOS variant".
#
# Usage:  verify-resilience-macos.sh [launchd-label]
#   label defaults to com.$USER.claude-remote
set -u

LABEL_ID="${1:-com.${USER}.claude-remote}"
PLIST="${HOME}/Library/LaunchAgents/${LABEL_ID}.plist"
SOCK="claude"      # must match SOCK in claude-remote-launch.sh
SESSION="main"     # must match SESSION in claude-remote-launch.sh
TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
fail=0; warn=0

ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
soft() { printf '  [WARN] %s\n' "$1"; warn=$((warn+1)); }
note() { printf '  [NOTE] %s\n' "$1"; }

echo "== Resilient-host (macOS) verification: ${LABEL_ID} =="
echo

# 1. LaunchAgent loaded + running ---------------------------------------------
if launchctl print "gui/$(id -u)/${LABEL_ID}" 2>/dev/null | grep -qE '^[[:space:]]*state = running'; then
  ok "LaunchAgent ${LABEL_ID} running"
else
  bad "LaunchAgent ${LABEL_ID} not running (launchctl bootstrap gui/\$(id -u) ${PLIST})"
fi

# 2. Starts at login + relaunches on crash (plist keys) ------------------------
if [ -f "${PLIST}" ] && grep -q 'RunAtLoad' "${PLIST}" && grep -q 'KeepAlive' "${PLIST}"; then
  ok "RunAtLoad + KeepAlive set (starts at login, relaunches on crash)"
else
  bad "RunAtLoad/KeepAlive not both found in ${PLIST}"
fi

# 3. tmux session present ------------------------------------------------------
if "${TMUX_BIN}" -L "${SOCK}" list-sessions 2>/dev/null | grep -q "^${SESSION}:"; then
  ok "tmux session '${SESSION}' present on -L ${SOCK}"
else
  bad "tmux session '${SESSION}' not found (claude may not be in its PTY)"
fi

# 4. claude --remote-control process alive ------------------------------------
if pgrep -f 'claude --remote-control' >/dev/null 2>&1; then
  ok "claude --remote-control process alive"
else
  bad "no claude --remote-control process"
fi

echo
echo "-- optional / unattended-boot layers (informational) --"

# 5. Power-on after power failure (settable AND readable on macoS, no sudo) ----
if pmset -g 2>/dev/null | grep -qE '^[[:space:]]*autorestart[[:space:]]+1'; then
  ok "pmset autorestart=1 (restarts after power failure)"
else
  soft "pmset autorestart=0 (set with: sudo pmset -a autorestart 1) -- only needed if you want power-on recovery"
fi

# 6. FileVault -- gates UNATTENDED boot ---------------------------------------
if fdesetup status 2>/dev/null | grep -q 'FileVault is On'; then
  note "FileVault is On: unattended reboot halts at the unlock screen. Fine for login-persistence (you unlock + log in); blocks true no-login boot."
else
  note "FileVault is Off: unattended boot can proceed (pair with auto-login + a LaunchDaemon/Agent for no-login start)."
fi

# 6b. Auto-login -- needed for unattended (no-login) boot ----------------------
ALU="$(defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser 2>/dev/null || true)"
if [ -n "${ALU}" ]; then
  note "auto-login enabled for '${ALU}' (unattended boot will start the agent)"
else
  note "auto-login off (fine for login-persistence; required for no-login boot)"
fi

# 7. Remote Login (SSH) -- needs sudo to read authoritatively ------------------
note "SSH (Remote Login): verify with 'sudo systemsetup -getremotelogin'; enable with 'sudo systemsetup -setremotelogin on'."

echo
echo "== Summary: ${fail} FAIL, ${warn} WARN =="
echo "Note: OS/kernel-hang recovery (hardware watchdog) is out of scope and not checked."
if [ "${fail}" -gt 0 ]; then
  echo "Login-persistence is NOT fully live. Do not call the host resilient yet."
  exit 1
fi
echo "Login-persistence layers pass: Claude remote control comes back on every login."
exit 0
