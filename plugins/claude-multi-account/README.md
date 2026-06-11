# claude-multi-account

One-time setup for running **two isolated Claude Code accounts** on one machine
— e.g. an enterprise/work login for sensitive projects alongside a personal one
— that can run at the same time in different terminals.

The mechanism is `CLAUDE_CONFIG_DIR`: it isolates credentials
(`.credentials.json`), settings, history, and MCP config per directory. The
skill installs a shell wrapper that scopes the env var to a single invocation,
so sessions never cross-contaminate:

```
claude        # the account that kept the default ~/.claude
claude-work   # the second account, pinned to ~/.claude-work
```

`/status` inside any session shows which account is active.

## The one rule that matters

**One launcher per config dir — never two on the same one.** Two independent
`claude` processes pointed at the same dir contend for a single credential slot,
and because OAuth refresh tokens are single-use (rotating), whichever process
refreshes first invalidates the persisted copy — so the other cold-starts into a
`/login` prompt. To avoid this, the skill keeps the already-logged-in account on
bare `claude` and wraps **only** the second account.

When the existing login is the *sensitive work* account, making it the bare
default would be backwards (you'd hit the sensitive profile on autopilot), so the
skill surfaces the trade-off and recommends an explicit `claude-work` wrapper
instead — a **symmetric** design where both accounts get their own dir and bare
`claude` goes unused. That costs one extra login but puts a deliberate command on
the sensitive account.

## What's in the box

| Path | What it is |
|---|---|
| `skills/claude-multi-account/SKILL.md` | The full setup procedure: detect shells, ask which account is which, install the managed shell block (PowerShell / bash / zsh), verify, guide the login, confirm both credential dirs, then self-delete. |

## Platforms

Windows PowerShell 5.1, PowerShell 7 (`pwsh`), bash, zsh, and Git Bash. The skill
writes a marker-delimited managed block into the relevant startup file(s)
idempotently (replace-in-place, never truncate).

## Setup

```
/plugin install claude-multi-account@hanifz-claude-skills
```

Then ask Claude to "set up multiple Claude Code accounts" (or separate work and
personal logins). The only manual step is a one-time `/login` for the second
account in a fresh terminal.

> **Note:** this is a **run-once** setup tool. After it verifies success it
> tells you so — installed as a plugin, retire it with
> `/plugin uninstall claude-multi-account@hanifz-claude-skills` (a manual
> drop-in install instead self-deletes its skill directory). The shell functions
> it installed live on in your profile/rc inside the
> `claude-multi-account (managed block)` markers regardless.

## Caveats

- Machine-wide **managed settings** deployed by enterprise IT apply to *both*
  accounts; they cannot be isolated per config dir.
- **Project-level** `.claude/settings.json` in a repo applies regardless of
  account — keep sensitive repos in the work profile by convention.
- Each config dir has its own user settings and MCP servers; configure them per
  profile as needed.

## License

MIT. See the repository `LICENSE`.
