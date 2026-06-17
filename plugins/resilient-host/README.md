# resilient-host

Set up — and **verify** — a host that keeps a Claude Code session
**remote-controllable** (from claude.ai / the mobile app on the same account) and
**reachable over SSH**, surviving power loss, unclean reboots, and the session
crashing. Supports **Linux/systemd** and **macOS/launchd**.

The design is **independent layers**, each covering one failure mode (Linux
mechanisms shown; see [macOS](#macos) for the launchd mapping):

| Failure mode | Layer |
|---|---|
| Claude session crashes / exits | systemd **user** service running `claude --remote-control` inside a dedicated **tmux** PTY, `Restart=always`, with an API-reachability pre-check |
| Reboot with nobody logged in | user **linger** (service starts at boot, unattended) |
| Service / SSH gone after reboot | `systemctl enable ssh` + linger |
| GRUB pause after unclean boot | `GRUB_TIMEOUT=0` + `GRUB_TIMEOUT_STYLE=hidden` |
| Power outage → power restored | BIOS "After Power Failure = Power On" (firmware, set at the machine) |

## Out of scope (for now)

Recovery from a **total OS/kernel hang** (where power never dropped) needs a
hardware watchdog (Intel TCO / `iTCO_wdt`). That layer is **not** part of this
skill yet — it will be added once it is fixed and armed on the host. Until then
the skill does **not** claim the host survives a kernel hang; it reports exactly
which layers are live.

## Privilege model

Privileged steps (linger, GRUB, SSH install/enable, BIOS) are **owner-run sudo
blocks** — sudo requires a password on this class of host, so the skill shows the
exact commands for the owner to run rather than executing them itself. Everything
else (the `claude-remote` user service and all verification) is user-level with no
sudo.

## macOS

macOS has no systemd or GRUB, so the layers map to **launchd**. Most desktop-Mac
owners (e.g. a Mac mini) want only **login-persistence**: "every time I restart
and log in, Claude remote control is just there." That's a **LaunchAgent** with
`RunAtLoad` + `KeepAlive` — no sudo, no FileVault changes.

Want it to come up **on boot with no login** instead? That requires **disabling
FileVault** (disk unencrypted at rest) plus **auto-login**. The skill **asks you
to choose** between the two modes and names the FileVault tradeoff up front — it
won't disable FileVault without explicit consent.

| Linux | macOS analog |
|---|---|
| systemd user service, `Restart=always` | **launchd LaunchAgent**, `RunAtLoad` + `KeepAlive`, inside tmux |
| linger (boot, no login) | owner login (login-persistence) — or auto-login (unattended; **FileVault-incompatible**) |
| `systemctl enable ssh` | Remote Login: `sudo systemsetup -setremotelogin on` |
| `GRUB_TIMEOUT=0` | N/A (no GRUB pause) |
| BIOS power-on (firmware) | `sudo pmset -a autorestart 1` (software-settable **and** readable) |

Two macOS gotchas, both rooted in **FileVault**: (1) with FileVault on, an
*unattended* reboot halts at the unlock screen (fine for login-persistence, blocks
no-login boot); (2) Claude's creds live in the **Keychain** (unlocked by GUI
login), so a LaunchAgent works but a root LaunchDaemon would not. Full details and
the trust-prompt / `node`-in-`PATH` gotchas are in `SKILL.md` → "macOS variant".

## What's in the box

| Path | What it is |
|---|---|
| `skills/resilient-host/SKILL.md` | Full per-layer setup + verify procedure (Linux **and** macOS). |
| `scripts/claude-remote.service` | **Linux** systemd **user** unit (templated `WorkingDirectory` + `<REMOTE_LABEL>`): tmux PTY, API pre-check, `Restart=always`. |
| `scripts/verify-resilience.sh` | **Linux** read-only checklist (no sudo): PASS/FAIL per layer. |
| `scripts/claude-remote.plist` | **macOS** LaunchAgent (templated `__USER__`): `RunAtLoad` + `KeepAlive`, tmux PTY. |
| `scripts/claude-remote-launch.sh` | **macOS** supervisor wrapper: API-wait → tmux → `claude --remote-control`, blocks so `KeepAlive` relaunches. |
| `scripts/verify-resilience-macos.sh` | **macOS** read-only checklist (no sudo for core layers): PASS/FAIL/WARN per layer. |

## Requirements

**Linux:**
- systemd (reference: Ubuntu 24.04 on an Intel NUC, no BMC/IPMI).
- `claude` on PATH, plus `tmux` and `curl`.
- Claude logged in with **file-based** credentials (`~/.claude/.credentials.json`,
  not the keyring), so a no-login boot can authenticate and refreshes persist.

**macOS:**
- macOS with launchd (reference: Mac mini M4 Pro, macOS 26) and Homebrew.
- `claude` on PATH, plus `tmux` (`brew install tmux`) and `curl`.
- Claude logged in normally — creds live in the **Keychain**, unlocked at GUI
  login (no credentials file needed; the Linux file-based prereq does not apply).

## Setup

```
/plugin install resilient-host@hanifz-claude-skills
```

Then ask Claude to "set up a reboot-resilient remote Claude host" or "verify my
resilient host". The skill walks the layers in order, hands you the sudo blocks to
run, and verifies each one — calling out exactly which layers are live and which
are not.

## License

MIT. See the repository `LICENSE`.
