---
name: claude-multi-account
description: >-
  One-time setup of two isolated Claude Code accounts (e.g. enterprise/work for
  sensitive projects + personal) that can run simultaneously. The account that
  is already logged in keeps the DEFAULT config dir and is launched with plain
  `claude` (no wrapper); the OTHER account gets a dedicated config dir and a
  single shell function (e.g. claude-work) that points CLAUDE_CONFIG_DIR there.
  Supports Windows PowerShell 5.1, PowerShell 7 (pwsh), bash, zsh, and Git Bash.
  TRIGGER when the user asks to set up multiple Claude Code accounts/profiles,
  separate work and personal Claude logins, or run two Claude accounts at once.
  This skill SELF-DELETES after setup is verified successful.
---

# Claude Code multi-account setup

You are performing a one-time machine setup. The mechanism: `CLAUDE_CONFIG_DIR`
isolates credentials (`.credentials.json`), settings, history, and MCP config
per directory.

**Design (important — read before installing):** create exactly ONE launcher
per account, and keep the already-logged-in account on the bare `claude`
command.

- The account already logged in stays in the DEFAULT config dir (`~/.claude`)
  and is launched with plain `claude` — no wrapper function for it.
- The OTHER account gets a dedicated NON-default dir (e.g. `~/.claude-work`) and
  a single shell function (e.g. `claude-work`) that scopes `CLAUDE_CONFIG_DIR`
  to it for that one invocation.

Do **not** create a wrapper that points `CLAUDE_CONFIG_DIR` at the *same*
default dir that bare `claude` already uses (e.g. a `claude-personal` ->
`~/.claude`). On keyring-backed machines (Linux gnome-keyring/libsecret, macOS
Keychain) that wrapper and bare `claude` become two independent processes
contending for ONE credential slot. OAuth refresh tokens are single-use
(rotating): whichever process refreshes first invalidates the persisted copy,
so the other cold-starts into a `/login` prompt. One launcher per account
avoids this entirely. (Each running `claude` keeps its live token in process
memory and only the persisted snapshot is shared — there is no IPC to hand a
fresh token between processes.)

Follow the steps in order. Do not skip verification, and do not self-delete
(step 7) unless verification passed.

## Step 1 — Gather facts (read-only)

1. Confirm Claude Code is installed: run `claude --version`.
2. Detect available shells and their startup files:
   - **Windows PowerShell 5.1**: profile path from `$PROFILE` inside
     `powershell.exe` (often under `Documents\WindowsPowerShell\`, possibly
     OneDrive-redirected).
   - **PowerShell 7**: if `pwsh` exists, its `$PROFILE` (under
     `Documents\PowerShell\`).
   - **bash**: `~/.bashrc` (on Windows, Git Bash uses this too; check that
     `bash` exists).
   - **zsh**: `~/.zshrc` (default shell on macOS).
   On Linux/macOS check `$SHELL` to know the user's primary shell.
3. Find which account is currently logged in to the default config:
   - Default config dir is `$CLAUDE_CONFIG_DIR` if set, else `~/.claude`.
   - The account email is in `oauthAccount.emailAddress` inside `~/.claude.json`
     (or `<config-dir>/.claude.json` when `CLAUDE_CONFIG_DIR` is set). Grep for
     `"emailAddress"` rather than JSON-parsing — the file can be large and, in
     Windows PowerShell 5.1, `ConvertFrom-Json` can fail on duplicate keys.
   - Check whether `<config-dir>/.credentials.json` exists (= already logged in).
   - Note: some commands that read credential stores may trip an auto-approval
     classifier. Keep each read narrowly scoped (separate `test -f` and `grep`
     calls), and if one is denied, explain that these are the skill's read-only
     fact-gathering steps before retrying with a simpler command.

## Step 2 — Ask the user

Use AskUserQuestion (skip anything already answered in conversation):

1. **Which shells to configure** (multiSelect, from those detected).
2. **Which account the existing default login is** — if a default-config login
   was found in step 1, show the email and ask whether it is the *personal* or
   the *work* account. Then resolve the design by the answer:

   - **Existing login is PERSONAL** → use the reuse design. Personal KEEPS the
     default `~/.claude` and is launched with plain `claude` (no wrapper). Work
     gets the wrapper `claude-work` → new `~/.claude-work`. No re-auth for
     personal; one login for work. This is the clean default.

   - **Existing login is WORK** → do NOT silently make work the bare default.
     The bare `claude` command is the one people invoke on autopilot, so making
     the *sensitive* work account the unlabeled default invites accidental
     cross-use. Surface the trade-off with a follow-up AskUserQuestion:

     | Option | Re-login? | Sensitive (work) account is launched by |
     | --- | --- | --- |
     | **A — Explicit work label (recommended)** | one (work → `~/.claude-work`) | `claude-work` (deliberate) |
     | **B — Reuse, no re-login** | none | bare `claude` (unlabeled — easy to hit by accident) |

     Recommend **A**: it puts an explicit, deliberate command on the sensitive
     account, which is the whole point of isolating work. There is no way to get
     an explicit `claude-work` AND reuse the existing token — an explicit
     wrapper needs a dedicated non-default dir, which needs its own login;
     pointing `claude-work` at the default dir would recreate the
     two-launchers-one-slot token race.

     - If the user picks **A**: this becomes the symmetric design (see the
       symmetric note at the end of Step 3). Both accounts get dedicated dirs —
       work → `~/.claude-work` (re-login once), personal → `~/.claude-personal`
       (login once) — and the user stops using bare `claude`. The existing
       default `~/.claude` is left unused. Install BOTH `claude-work` and
       `claude-personal` wrappers.
     - If the user picks **B**: use the reuse design with roles swapped — work
       KEEPS the default `~/.claude` (plain `claude`, no re-auth) and personal
       gets the wrapper `claude-personal` → new `~/.claude-personal`.

   In all cases the rule from the top holds: never install a wrapper whose
   `CLAUDE_CONFIG_DIR` points at the same default dir that bare `claude` uses.

## Step 3 — Install the wrapper (idempotent)

Write a marker-delimited block into each selected startup file. If the markers
already exist, REPLACE the block between them instead of appending a duplicate.
Create the startup file (and parent directory) if missing — never truncate an
existing file; append or replace-block only.

Markers: `# --- claude-multi-account (managed block) ---` and
`# --- end claude-multi-account ---`.

Install a wrapper ONLY for the account that does NOT keep the default dir.
`<OTHER_NAME>` is `claude-work` or `claude-personal` (whichever is NOT the
existing default login); `<OTHER_DIR>` is its new dedicated dir
(`~/.claude-work` or `~/.claude-personal`). Substitute real absolute paths.

**PowerShell (5.1 and 7 — same block in each profile file):**

```powershell
# --- claude-multi-account (managed block) ---
# <OTHER_NAME> -> the second account (<OTHER_DIR>)
# The account already logged in uses plain `claude` (default config dir).
# Env var is scoped to the single invocation, then restored.
function Invoke-ClaudeWithConfig {
    param([string]$ConfigDir, [object[]]$RemainingArgs)
    $prev = $env:CLAUDE_CONFIG_DIR
    $env:CLAUDE_CONFIG_DIR = $ConfigDir
    try {
        claude @RemainingArgs
    }
    finally {
        if ($null -eq $prev) {
            Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:CLAUDE_CONFIG_DIR = $prev
        }
    }
}
function <OTHER_NAME> { Invoke-ClaudeWithConfig -ConfigDir "<OTHER_DIR>" -RemainingArgs $args }
# --- end claude-multi-account ---
```

**bash / zsh (same block in `~/.bashrc` and/or `~/.zshrc`):**

```bash
# --- claude-multi-account (managed block) ---
# <OTHER_NAME> -> the second account (<OTHER_DIR>)
# The account already logged in uses plain `claude` (default config dir),
# so it never races this wrapper over the single-use OAuth token.
# The VAR=value prefix scopes the env var to the single invocation.
<OTHER_NAME>() { CLAUDE_CONFIG_DIR="<OTHER_DIR>" claude "$@"; }
# --- end claude-multi-account ---
```

(Hyphenated function names are fine in bash and zsh, but not POSIX `sh`/dash —
only install into bash/zsh startup files.)

Windows note: if PowerShell's execution policy is `Restricted`
(`Get-ExecutionPolicy -List`), profiles will not load; set
`Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` after telling the user.

**SYMMETRIC design** (both `claude-work` and `claude-personal`, no bare `claude`
for either): use this when Step 2 selected it — either the user asked for
symmetric names, or the existing login is WORK and the user picked option A
(explicit work label). Give BOTH accounts dedicated non-default dirs
(`~/.claude-work` and `~/.claude-personal`), install a wrapper for each in the
same managed block, and tell the user to stop using bare `claude`. BOTH dirs
then need a login in Step 5 (the existing default login does not carry over into
a dedicated dir — for the single-use-token reasons above, it must be re-done
once in the new dir). The asymmetric reuse design above is lower-friction (no
re-auth); prefer it unless Step 2 steered here.

Symmetric bash/zsh block:

```bash
# --- claude-multi-account (managed block) ---
# claude-work     -> work/enterprise account (<WORK_DIR>)
# claude-personal -> personal account        (<PERSONAL_DIR>)
# Both use dedicated dirs; do not use bare `claude`.
claude-work()     { CLAUDE_CONFIG_DIR="<WORK_DIR>"     claude "$@"; }
claude-personal() { CLAUDE_CONFIG_DIR="<PERSONAL_DIR>" claude "$@"; }
# --- end claude-multi-account ---
```

(PowerShell: define two functions, each calling `Invoke-ClaudeWithConfig` with
its own dir.)

## Step 4 — Verify

For each configured shell, load the startup file in a fresh shell process and
run the wrapper with `--version`, plus bare `claude --version`:

- PowerShell: `powershell -Command ". $PROFILE; <OTHER_NAME> --version"`
  (and the same with `pwsh` if configured)
- bash: `bash -ic "<OTHER_NAME> --version"` — the `-i` (interactive) flag is
  REQUIRED: stock Ubuntu/Debian `~/.bashrc` starts with an interactive-shell
  guard (`case $- in *i*) ;; *) return;; esac`), so a plain
  `bash -c "source ~/.bashrc; ..."` returns before reaching the managed block
  and reports "command not found" even when the install is correct.
- zsh: `zsh -ic "<OTHER_NAME> --version"`

Each must print a version with no errors. Also confirm the env var does not
leak: after the PowerShell function returns, `$env:CLAUDE_CONFIG_DIR` must be
back to its prior value. Fix any failure before continuing.

## Step 5 — User logs in

Tell the user (this is the only manual step). Open a NEW terminal first (so the
profile/rc loads), then:

- **Asymmetric reuse design** (existing login kept on bare `claude`): log in
  only ONCE — run the wrapper for the second account (e.g. `claude-work`), then
  `/login`. The first account needs no login; it reuses the existing default
  credentials via plain `claude`.
- **Symmetric design** (both wrapped, no bare `claude`): log in TWICE — run
  `claude-work` → `/login` with the work account, then `claude-personal` →
  `/login` with the personal account. Each token persists after its one login.

## Step 6 — Confirm success

Setup is successful only when BOTH of the account config dirs contain
`.credentials.json`:

- Asymmetric reuse: the default `~/.claude` (already present from the existing
  login) plus the new `<OTHER_DIR>/.credentials.json`.
- Symmetric: both `~/.claude-work/.credentials.json` and
  `~/.claude-personal/.credentials.json` (the default `~/.claude` is unused
  here and does not need to be checked).

If a required one is missing, ask the user whether
they completed `/login` (AskUserQuestion is fine here, or just wait), then
re-check. Do not proceed to step 7 on failure or on "I'll do it later" — in that
case leave the skill installed and tell the user to re-invoke it to finish.

## Step 7 — Retire the skill (it is single-use)

This skill is a run-once setup tool; once setup is verified there is no reason
to keep it loaded. After step 6 confirms success, retire it the way that matches
how it was installed — do NOT blindly `rm` files:

1. **Installed as a plugin** (it lives under a plugin path, e.g.
   `.../plugins/.../claude-multi-account/`, and `/plugin` manages it): do NOT
   delete files inside the plugin — the plugin manager owns them and would
   restore or error. Instead tell the user the one-off is done and they can
   remove it with:
   `/plugin uninstall claude-multi-account@hanifz-claude-skills`
   (Leaving it installed is harmless too; it just stays loaded as a skill.)
2. **Manually installed skill** (its own dir at `~/.claude/skills/claude-multi-account/`):
   verify the directory name is exactly `claude-multi-account` and it contains
   `SKILL.md`, tell the user it will remove itself, then delete that one
   directory recursively. Delete nothing else.
3. **Run from an extracted archive**: "retire" means removing that temp extract;
   never delete the user's original archive without asking.

Then remind the user how to use the two accounts:
   - Asymmetric reuse: plain `claude` -> the account that kept the default dir;
     `<OTHER_NAME>` -> the second account.
   - Symmetric: `claude-work` and `claude-personal` -> their respective
     accounts; do not use bare `claude`.
   `/status` inside a session shows the active account.

## Caveats to mention to the user at the end

- One launcher per account by design — never two launchers on one config dir.
  In the asymmetric reuse design the already-logged-in account stays on bare
  `claude` and only the second account is wrapped; in the symmetric design each
  account has its own wrapper and dir and bare `claude` is unused. Either way no
  two processes contend for one credential slot, which is what caused the
  single-use-token re-login prompts.
- Machine-wide **managed settings** deployed by enterprise IT apply to BOTH
  accounts; they cannot be isolated per config dir.
- **Project-level** `.claude/settings.json` in a repo applies regardless of
  account. Keep sensitive repos in the work profile by convention.
- Each config dir has its own user settings and MCP servers — configure them
  per profile as needed.
