# resilient-host

Set up — and **verify** — a Linux host that keeps a Claude Code session
**remote-controllable** (from claude.ai / the mobile app on the same account) and
**reachable over SSH**, surviving power loss, unclean reboots, and the session
crashing.

The design is **independent layers**, each covering one failure mode:

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

## What's in the box

| Path | What it is |
|---|---|
| `skills/resilient-host/SKILL.md` | Full per-layer setup + verify procedure. |
| `scripts/claude-remote.service` | The systemd **user** unit (templated `WorkingDirectory` + `<REMOTE_LABEL>`): tmux PTY, API pre-check, `Restart=always`. |
| `scripts/verify-resilience.sh` | End-to-end read-only checklist (no sudo): PASS/FAIL per layer. |

## Requirements

- Linux with **systemd** (reference: Ubuntu 24.04 on an Intel NUC, no BMC/IPMI).
- `claude` on PATH, plus `tmux` and `curl`.
- Claude logged in via claude.ai with **file-based** credentials
  (`~/.claude/.credentials.json`, not the keyring), so a no-login boot can
  authenticate and token refreshes persist.

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
