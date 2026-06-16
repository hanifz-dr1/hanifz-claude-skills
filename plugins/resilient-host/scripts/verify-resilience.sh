#!/usr/bin/env bash
# Verify every resilience layer end to end. Read-only; NO sudo required.
#
# Prints one PASS / FAIL / WARN line per layer and a summary.
#
# NOTE: OS/kernel-hang recovery (a hardware watchdog) is intentionally out of
# scope for this skill and is NOT checked here -- it will be added later.
#
# Usage:  verify-resilience.sh [user]
#   user defaults to the current $USER (used for the linger check).

set -u

USER_NAME="${1:-$USER}"
fail=0
warn=0

ok()   { printf '  [PASS] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=$((fail+1)); }
soft() { printf '  [WARN] %s\n' "$1"; warn=$((warn+1)); }

echo "== Resilient-host verification (user: ${USER_NAME}) =="
echo

# 1. Claude auto-start user service -------------------------------------------
if systemctl --user is-active claude-remote >/dev/null 2>&1; then
  ok "claude-remote.service active"
else
  bad "claude-remote.service NOT active"
fi
if systemctl --user is-enabled claude-remote >/dev/null 2>&1; then
  ok "claude-remote.service enabled"
else
  bad "claude-remote.service NOT enabled"
fi

# 2. tmux session present ------------------------------------------------------
if tmux -L claude list-sessions 2>/dev/null | grep -q '^main:'; then
  ok "tmux session 'main' present on -L claude"
else
  bad "tmux session 'main' not found (claude may not be running in its PTY)"
fi

# 3. Linger --------------------------------------------------------------------
if loginctl show-user "${USER_NAME}" 2>/dev/null | grep -q '^Linger=yes'; then
  ok "linger enabled (service starts at boot with no login)"
else
  bad "linger NOT enabled -- service will not start until ${USER_NAME} logs in"
fi

# 4. SSH -----------------------------------------------------------------------
if systemctl is-active ssh >/dev/null 2>&1; then ok "ssh active"; else bad "ssh NOT active"; fi
if systemctl is-enabled ssh >/dev/null 2>&1; then ok "ssh enabled"; else bad "ssh NOT enabled"; fi

# 5. GRUB (no pause on unclean boot) ------------------------------------------
if grep -Eq '^GRUB_TIMEOUT=0$' /etc/default/grub 2>/dev/null \
   && grep -Eq '^GRUB_TIMEOUT_STYLE=hidden$' /etc/default/grub 2>/dev/null; then
  ok "GRUB_TIMEOUT=0 + GRUB_TIMEOUT_STYLE=hidden"
else
  soft "GRUB timeout/style not both set (check /etc/default/grub, then update-grub)"
fi

# 6. BIOS power-on rule -- cannot be read from the OS on this NUC --------------
soft "BIOS 'After Power Failure = Power On' is firmware-only -- verify at the machine (F2)"

echo
echo "== Summary: ${fail} FAIL, ${warn} WARN =="
echo "Note: OS/kernel-hang recovery (hardware watchdog) is out of scope and not checked."
if [ "${fail}" -gt 0 ]; then
  echo "One or more resilience layers are NOT live. Do not call the host resilient yet."
  exit 1
fi
echo "All OS-checkable layers pass. Confirm the BIOS power-on rule at the machine."
exit 0
