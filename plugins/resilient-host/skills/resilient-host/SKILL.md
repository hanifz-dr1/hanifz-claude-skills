---
name: resilient-host
description: >-
  Set up (and verify) a Linux host that keeps a Claude Code session
  remote-controllable from claude.ai / the mobile app and reachable over SSH
  across reboots and power loss. Builds independent layers: a systemd USER
  service running `claude --remote-control` inside a dedicated tmux PTY
  (Restart=always + an API-reachability pre-check), user LINGER so it starts at
  boot with no login, SSH enabled, GRUB hidden/zero-timeout, and a BIOS power-on
  rule. TRIGGER when the user wants a reboot/power-loss-resilient remote Claude
  host, an auto-restarting headless claude session, or to verify/repair such a
  setup. Privileged steps are owner-run sudo blocks. NOTE: OS/kernel-hang
  recovery (a hardware watchdog) is intentionally OUT OF SCOPE here and will be
  added later — do not claim the host survives a total kernel hang.
---

# Resilient remote-control Claude host

Goal: keep a Claude Code session **remote-controllable** (from claude.ai / the
mobile app on the same account) and **reachable over SSH**, surviving:

- power outage → power restored,
- unclean reboot / GRUB hang,
- the Claude session itself crashing or exiting,
- a plain reboot with nobody logged in.

Each failure mode is covered by a **distinct layer**. They are independent — one
being down does not break the others, and you must report each one's true state
rather than assuming "set up" means "live".

**Out of scope (for now):** recovery from a **total OS/kernel hang** where power
never dropped. That requires a hardware watchdog (Intel TCO / `iTCO_wdt`), which
is **not** part of this skill yet — it will be added once it is fixed and armed
on the host. Until then, do **not** claim the host survives a kernel hang.

## Bundled files

Reference these from the plugin's `scripts/` directory; substitute real paths
before deploying.

| File | What it is |
|---|---|
| `scripts/claude-remote.service` | The systemd **user** unit (templated: `WorkingDirectory`, `<REMOTE_LABEL>`). |
| `scripts/verify-resilience.sh` | End-to-end read-only checklist (no sudo); PASS/FAIL per layer. |

## Privilege model

- **User-level steps** (the `claude-remote` service, `systemctl --user`, reading
  state) run as the owner with **no sudo**.
- **Privileged steps** (linger, GRUB, installing/enabling SSH, BIOS) need **sudo**
  and on this class of host sudo **requires a password** — `sudo -n` does not
  work. Present these as **owner-run sudo blocks**: show the exact commands and
  have the owner run them interactively. Do not assume you can execute them
  yourself.

## Host assumptions (adjust to the real host)

- Linux with **systemd** (reference host: Ubuntu 24.04 LTS on an Intel NUC7i3BNH,
  **no BMC/IPMI**).
- `claude` on PATH (e.g. `~/.local/bin/claude`), plus `tmux` and `curl`.
- Claude already logged in via claude.ai with credentials in a **plain file**
  `~/.claude/.credentials.json` (mode 600), **not** the system keyring — so
  headless/lingering boots can authenticate and token refreshes persist. If the
  login is keyring-backed, a no-login boot may not unlock it; convert to the
  file-based credential first.

---

## Layer → failure-mode map

| # | Failure mode | Recovery mechanism | Verify with |
|---|---|---|---|
| 1 | Claude session crashes / exits | systemd **user** service, `Restart=always`, inside tmux PTY | `systemctl --user is-active claude-remote` |
| 2 | Reboot with nobody logged in | **linger** for the user | `loginctl show-user <user> \| grep Linger` |
| 3 | Service / SSH gone after reboot | `systemctl enable ssh` + linger | `systemctl is-enabled ssh` |
| 4 | GRUB pause after unclean boot | `GRUB_TIMEOUT=0` + `GRUB_TIMEOUT_STYLE=hidden` | `grep GRUB_TIMEOUT /etc/default/grub` |
| 5 | Power outage, then power returns | BIOS "After Power Failure = Power On" (firmware) | at the machine (F2) — not OS-readable |

---

## Layer 1 — Claude auto-start user service

Unit: `~/.config/systemd/user/claude-remote.service` (a **user** service). Deploy
from `scripts/claude-remote.service`, substituting `WorkingDirectory` and
`<REMOTE_LABEL>` (the session label shown in claude.ai / the mobile app).

Why it is built the way it is — keep these properties if you edit it:

- Runs `claude --remote-control <label>` **inside a dedicated tmux server**
  (`tmux -L claude`, session `main`). tmux is **required**: without a real PTY,
  `claude --remote-control` falls back to `--print` mode and refuses to start an
  interactive session.
- **Blocks in `ExecStartPre` until the Anthropic API is reachable** before
  launching Claude. This is deliberate: `claude --remote-control` does **not**
  exit when it can't reach the network — it sits there with "/rc failed", so
  `Restart=always` would never fire. The pre-check waits up to ~60s for DNS + TLS
  to `api.anthropic.com`, then exits non-zero on timeout so Restart retries.
  (`network-online.target` is not visible to the user manager, which is why we
  poll the API directly rather than ordering after it.)
- `Type=forking` because `tmux new-session -d` forks and returns.
- A stale tmux server is killed in `ExecStartPre` before (re)start so restarts
  are clean.

Install:
```bash
# Copy scripts/claude-remote.service -> ~/.config/systemd/user/claude-remote.service
# (edit WorkingDirectory and <REMOTE_LABEL> first), then:
systemctl --user daemon-reload
systemctl --user enable --now claude-remote
```

Manage / observe (all user-level, no sudo):
```bash
systemctl --user status claude-remote
systemctl --user restart claude-remote
tmux -L claude attach -t main        # watch the live session; detach with Ctrl-b d
```

## Layer 2 — Linger (start at boot with no login)

Without linger the user manager (and the user service) only runs while the user
is logged in. Linger makes it start at boot unattended.

**Owner-run sudo:**
```bash
sudo loginctl enable-linger <user>
```
Verify (no sudo): `loginctl show-user <user> | grep Linger` → `Linger=yes`.

## Layer 3 — SSH reachable after reboot

**Owner-run sudo:**
```bash
sudo apt install -y openssh-server
sudo systemctl enable --now ssh
```
Verify (no sudo): `systemctl is-active ssh && systemctl is-enabled ssh`.

Hardening to mention (not required for resilience, but call it out): if
`~/.ssh/authorized_keys` is empty, inbound login relies on **password auth**. For
off-LAN access there is no VPN/overlay by default — a tunnel (e.g. Tailscale) or
port-forward is needed. (An outbound git deploy key like `~/.ssh/id_ed25519` is a
*client* key and does **not** grant inbound login — don't conflate the two.)

## Layer 4 — GRUB (no pause on unclean boot)

Prevents the ~30s `recordfail` pause after an unclean shutdown that would
otherwise stall an unattended reboot.

**Owner-run sudo** — set in `/etc/default/grub`:
```
GRUB_TIMEOUT=0
GRUB_TIMEOUT_STYLE=hidden
```
then `sudo update-grub`. Verify (no sudo): `grep -E 'GRUB_TIMEOUT(_STYLE)?' /etc/default/grub`.

## Layer 5 — BIOS power-on (at the machine)

Not settable from the OS on this NUC. **Owner, at the machine:** F2 at boot →
Power → Secondary Power Settings → **After Power Failure = Power On**. This is the
only thing that recovers a real power outage; you cannot read or verify it from
software — confirm with the owner.

---

## Reproduce from scratch (ordered)

Privileged steps are owner-run sudo blocks.

1. **Prereqs** (no sudo): confirm `claude --version`, `tmux -V`, `curl --version`,
   and that `~/.claude/.credentials.json` exists (file-based login).
2. **Layer 1** (no sudo): deploy `scripts/claude-remote.service` →
   `~/.config/systemd/user/claude-remote.service` (edit `WorkingDirectory` +
   `<REMOTE_LABEL>`), then `systemctl --user daemon-reload && systemctl --user enable --now claude-remote`.
3. **Layer 2 — linger** (sudo): `sudo loginctl enable-linger <user>`.
4. **Layer 3 — SSH** (sudo): `sudo apt install -y openssh-server && sudo systemctl enable --now ssh`.
5. **Layer 4 — GRUB** (sudo): set the two GRUB values, `sudo update-grub`.
6. **Layer 5 — BIOS** (at the machine): set After Power Failure = Power On.

## Verify (read-only, no sudo)

Run the bundled checklist; it prints PASS/FAIL per layer:
```bash
scripts/verify-resilience.sh <user>
```
Equivalent manual checks:
```bash
systemctl --user is-active claude-remote && systemctl --user is-enabled claude-remote  # active / enabled
loginctl show-user <user> | grep Linger                                                # Linger=yes
systemctl is-active ssh && systemctl is-enabled ssh                                     # active / enabled
grep -E 'GRUB_TIMEOUT(_STYLE)?' /etc/default/grub                                       # 0 / hidden
tmux -L claude list-sessions                                                            # 'main' present
```

When reporting status, enumerate exactly which layers are live and which are not.
Remember the **OS/kernel-hang** case is **not covered** by this skill yet — say so
rather than implying full resilience.
