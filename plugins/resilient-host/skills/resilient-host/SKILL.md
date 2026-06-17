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
  setup — on Linux/systemd OR on macOS (a launchd LaunchAgent that brings the
  `claude --remote-control` tmux session back on every login; see the "macOS
  variant" section for the Mac mini / iMac case and its FileVault/Keychain
  caveats). Privileged steps are owner-run sudo blocks. NOTE: OS/kernel-hang
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
| `scripts/claude-remote.service` | **Linux** systemd **user** unit (templated: `WorkingDirectory`, `<REMOTE_LABEL>`). |
| `scripts/verify-resilience.sh` | **Linux** end-to-end read-only checklist (no sudo); PASS/FAIL per layer. |
| `scripts/claude-remote.plist` | **macOS** LaunchAgent (templated: `__USER__`; edit `LABEL`/`WORKDIR` in the wrapper). |
| `scripts/claude-remote-launch.sh` | **macOS** supervisor wrapper: API-wait → tmux PTY → `claude --remote-control`, blocks so launchd can relaunch. |
| `scripts/verify-resilience-macos.sh` | **macOS** read-only checklist (no sudo for core layers); PASS/FAIL/WARN per layer. |

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

---

## macOS variant (launchd)

macOS has none of the Linux primitives (no systemd, no GRUB), so the layers map
to different mechanisms. **First decide which goal applies — they need different
amounts of work:**

- **Login-persistence (the common case, e.g. a Mac mini you log into):** "every
  time I restart and log in, Claude remote control is just there." This is
  **Layer 1 only**, done with a **launchd LaunchAgent** — no sudo, no FileVault
  changes. Recommended default for a desktop Mac.
- **Unattended (no-login) boot:** the Linux-style "comes up with nobody logged
  in." On macOS this is gated by FileVault and the Keychain — see the caveats
  below. Usually **not** what a desktop-Mac owner wants.

### OS-primitive mapping

| # | Failure mode | Linux | macOS analog |
|---|---|---|---|
| 1 | Session crashes/exits | systemd user service, `Restart=always` | **launchd LaunchAgent**, `KeepAlive=true` + `RunAtLoad=true`, inside tmux |
| 2 | Reboot — no one logged in | linger | **owner logs in** (login-persistence) *or* **auto-login** (unattended; FileVault-incompatible) |
| 3 | SSH after reboot | `systemctl enable ssh` | **Remote Login**: `sudo systemsetup -setremotelogin on` |
| 4 | Bootloader pause | `GRUB_TIMEOUT=0` | **N/A** — Macs have no GRUB pause |
| 5 | Power outage → restored | BIOS (firmware, unreadable) | `sudo pmset -a autorestart 1` — **software-settable AND readable** |

### Two macOS-specific caveats (both = FileVault)

- **FileVault gates unattended boot.** With FileVault **on**, a reboot/power-restore
  halts at the pre-boot unlock screen until someone types the password at the
  machine — so SSH, launchd jobs, and Claude all stay down until then. This does
  **not** affect login-persistence (you unlock + log in, then the agent fires).
  True no-login boot requires turning FileVault **off** (disk unencrypted at rest
  — a real security tradeoff) plus **auto-login** (which FileVault disables).
- **Credentials are Keychain-backed, not a file.** On macOS, Claude stores creds
  in the login Keychain (`Claude Code-credentials`), which is unlocked by GUI
  login. A LaunchAgent in the Aqua session inherits the unlocked Keychain, so it
  authenticates fine. A root LaunchDaemon (no GUI login) would **not** — another
  reason login-persistence is the clean path. (There is no `~/.claude/.credentials.json`
  on macOS; that Linux prereq does not apply.)

### Layer 1 — LaunchAgent (login-persistence)

A **LaunchAgent** runs in the user's GUI session, so it starts at login with the
Keychain already unlocked. Deploy from `scripts/`:

1. `brew install tmux` (required — `claude --remote-control` needs a real PTY).
2. Copy `scripts/claude-remote-launch.sh` → `~/.local/bin/claude-remote-launch.sh`,
   `chmod +x`, and edit `LABEL` (the name shown in claude.ai / the mobile app) and
   `WORKDIR` at the top.
3. Copy `scripts/claude-remote.plist` → `~/Library/LaunchAgents/com.$USER.claude-remote.plist`,
   then replace every `__USER__` **inside** the file with your username (`echo $USER`).
   Keep `RunAtLoad`+`KeepAlive` (start-at-login +
   relaunch-on-crash) and the `PATH` (include the Homebrew prefix **and** wherever
   `node` lives, or user Stop hooks fail with `node: command not found`).
4. Load + start now:
   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.$USER.claude-remote.plist
   launchctl kickstart -k gui/$(id -u)/com.$USER.claude-remote
   ```

Why the wrapper blocks (don't "fix" it): launchd `KeepAlive` relaunches the
ProgramArguments when they exit. `tmux new-session -d` forks and returns
immediately, which would make launchd respawn in a tight loop. So the wrapper
starts the detached session, then **blocks on `tmux has-session`** and only exits
when Claude actually dies — that's what makes `KeepAlive` behave like
`Restart=always`. The API-reachability wait is the same idea as the Linux unit's
`ExecStartPre`.

On first launch Claude shows a **"trust this folder"** prompt for `WORKDIR`; it
blocks remote control until answered. Confirm it once (`tmux -L claude attach -t main`,
press Enter) — trust persists, so later relaunches go straight to `/rc active`.

Manage / observe (all user-level, no sudo):
```bash
tmux -L claude attach -t main                              # watch live; detach Ctrl-b d
launchctl kickstart -k gui/$(id -u)/com.$USER.claude-remote   # restart
launchctl bootout    gui/$(id -u)/com.$USER.claude-remote     # stop
tail -f ~/.claude/claude-remote.err.log                   # supervisor log
```

### Layers 3 & 5 — optional, only for unattended use

- **SSH (Layer 3), owner-run sudo:** `sudo systemsetup -setremotelogin on`
  (persists across reboot). Verify: `sudo systemsetup -getremotelogin`.
- **Power-on after outage (Layer 5), owner-run sudo:** `sudo pmset -a autorestart 1`.
  Verify (no sudo): `pmset -g | grep autorestart` → `1`. Better than the NUC —
  this is readable from software. Also keep it awake: `sudo pmset -a sleep 0`.

### Verify (macOS)

```bash
scripts/verify-resilience-macos.sh [com.$USER.claude-remote]
```
PASS/FAIL on the login-persistence layers (LaunchAgent running, RunAtLoad+KeepAlive,
tmux session, claude process); WARN/NOTE on the optional unattended layers
(`pmset autorestart`, FileVault, SSH). The **kernel-hang** caveat applies on macOS
too — there is no user watchdog here either.
