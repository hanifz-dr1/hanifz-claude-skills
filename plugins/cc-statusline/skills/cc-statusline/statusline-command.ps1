# Claude Code status line (up to 4 lines, dashboard layout) — Windows PowerShell
# port of statusline-command.sh (keep the two in sync; same layout + line-4 logic):
#   Line 1: model · cwd (home shortened to ~)
#   Line 2: git — upstream repo (owner/group/name) + "⎇ <branch>"
#           (detached HEAD -> short sha; no remote -> branch only; not a repo -> "⎇ no git")
#   Line 3: context window — labeled progress bar + token counts
#   Line 4: usage — subscription rate-limit windows (5h & 7d), OR, for
#           enterprise/API/Bedrock/Vertex/Foundry/gateway billing,
#           "session cost $X · duration Y" (mode-prefixed when an env var names it).
#
# Reads the status-line JSON payload from stdin (the CLI pipes it on each render).
# Every segment degrades gracefully: a field absent from the payload is omitted and
# its line dropped. `rate_limits` only appears for claude.ai subscription auth and
# only once the session has seen an API response — see SKILL.md for the contract.
#
# Targets Windows PowerShell 5.1 (powershell.exe). Wire it into settings.json with
# a FORWARD-SLASH path — Claude Code routes the statusLine command through Git Bash
# when it is installed, and bash strips unquoted backslashes:
#   "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:/Users/<you>/.claude/statusline-command.ps1"
#
# NB: keep this file ASCII-only (glyphs are emitted via [char]0x....) — PowerShell
# 5.1 reads BOM-less UTF-8 source as ANSI and would mangle literal glyphs.

# Force UTF-8 in/out so the bar/branch glyphs render correctly through the pipe.
try {
  $utf8 = New-Object System.Text.UTF8Encoding($false)
  [Console]::OutputEncoding = $utf8
  [Console]::InputEncoding  = $utf8
} catch { }

# --- read stdin (robust across invocation styles) ---------------------------
# Claude Code may spawn this directly (real OS pipe -> [Console]::In works) or
# via a parent shell that forwards piped input as the $input enumerator.
$raw = $null
try { $raw = [Console]::In.ReadToEnd() } catch { }
if ([string]::IsNullOrWhiteSpace($raw)) {
  try { $raw = ($input | Out-String) } catch { }
}

if ([string]::IsNullOrWhiteSpace($raw)) { exit 0 }
try { $j = $raw | ConvertFrom-Json } catch { exit 0 }

# --- helpers ----------------------------------------------------------------
function Make-Bar($p, $w = 14) {
  $p = [double]$p
  if ($p -lt 0) { $p = 0 }; if ($p -gt 100) { $p = 100 }
  $n = [int][math]::Round($p * $w / 100)
  if ($n -lt 0) { $n = 0 }; if ($n -gt $w) { $n = $w }
  return ([string][char]0x2588 * $n) + ([string][char]0x2591 * ($w - $n))
}

function Format-Tokens($n) {
  $n = [double]$n
  if ($n -ge 1000000) {
    $v = $n / 1000000
    if ($v -eq [math]::Floor($v)) { return ('{0}M' -f [int]$v) }
    return ('{0:0.0}M' -f $v)
  }
  return ('{0}k' -f [int][math]::Round($n / 1000))
}

# Humanize a reset timestamp (epoch seconds OR ISO-8601) -> "1h23m" / "3d4h" / "45m".
# Returns '' when missing, past, or unparseable.
function Format-Reset($ra) {
  if ($null -eq $ra -or "$ra" -eq '') { return '' }
  $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
  $target = $null
  if ("$ra" -match '^[0-9]+$') {
    $target = [int64]"$ra"
  } else {
    try { $target = [DateTimeOffset]::Parse("$ra", $null, [System.Globalization.DateTimeStyles]::AssumeUniversal).ToUnixTimeSeconds() } catch { return '' }
  }
  if ($null -eq $target) { return '' }
  $delta = $target - $now
  # Sanity guard: windows are <=7d; a huge delta means resets_at was in milliseconds.
  if ($delta -gt 2592000) { $delta = [int64]($target / 1000) - $now }
  if ($delta -le 0) { return '' }
  $d = [math]::Floor($delta / 86400)
  $h = [math]::Floor(($delta % 86400) / 3600)
  $m = [math]::Floor(($delta % 3600) / 60)
  if ($d -gt 0) { return ('{0}d{1}h' -f $d, $h) }
  elseif ($h -gt 0) { return ('{0}h{1}m' -f $h, $m) }
  else { return ('{0}m' -f $m) }
}

# Humanize a millisecond duration -> "1h9m" / "12m34s" / "45s". '' if empty/zero.
function Format-Duration($ms) {
  if ($null -eq $ms -or "$ms" -notmatch '^[0-9]+$') { return '' }
  $s = [int64]([int64]"$ms" / 1000)
  if ($s -le 0) { return '' }
  $h = [math]::Floor($s / 3600)
  $m = [math]::Floor(($s % 3600) / 60)
  $sec = $s % 60
  if ($h -gt 0) { return ('{0}h{1}m' -f $h, $m) }
  elseif ($m -gt 0) { return ('{0}m{1}s' -f $m, $sec) }
  else { return ('{0}s' -f $sec) }
}

# Run git, swallow all errors (incl. git not installed), return first output line or $null.
function Invoke-Git([string[]]$gitArgs) {
  try {
    $out = & git @gitArgs 2>$null
    if ($LASTEXITCODE -eq 0 -and $out) { return ($out | Select-Object -First 1) }
  } catch { }
  return $null
}

# --- line 1: model + cwd ----------------------------------------------------
$model = $j.model.display_name
if (-not $model) { $model = 'Claude' }

$cwdRaw = $j.workspace.current_dir
if (-not $cwdRaw) { $cwdRaw = $j.cwd }
if (-not $cwdRaw) { $cwdRaw = '' }
$cwd = $cwdRaw
if ($cwd -and $HOME -and $cwd.StartsWith($HOME, [System.StringComparison]::OrdinalIgnoreCase)) {
  $cwd = '~' + $cwd.Substring($HOME.Length)
}

# --- line 2: git — upstream repo path + branch -------------------------------
#   In a repo  -> "<owner/group>/<repo> ⎇ <branch>" (short sha when detached;
#                 repo prefix dropped if no remote). Not a repo -> "⎇ no git".
# The repo path is parsed from the upstream remote's URL — SSH (git@host:owner/repo.git),
# HTTPS (https://host/owner/repo.git), and nested groups (gitlab.com/grp/sub/repo) all
# map to the full namespace path with host and trailing .git stripped.
$alt = [string][char]0x2387   # ⎇
$branchSegment = ''
if ($cwdRaw) {
  $br = Invoke-Git @('-C', $cwdRaw, 'rev-parse', '--abbrev-ref', 'HEAD')
  if ($br) {
    if ($br -eq 'HEAD') { $br = Invoke-Git @('-C', $cwdRaw, 'rev-parse', '--short', 'HEAD') }
    # Remote backing the current branch's upstream, else origin, else the first remote.
    $remote = ''
    $up = Invoke-Git @('-C', $cwdRaw, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{upstream}')
    if ($up) { $remote = ($up -split '/')[0] }
    if (-not $remote) { $remote = 'origin' }
    if ($null -eq (Invoke-Git @('-C', $cwdRaw, 'remote', 'get-url', $remote))) {
      $remote = Invoke-Git @('-C', $cwdRaw, 'remote')
    }
    # Repo path from the remote URL: strip scheme+host (HTTPS), user@host (SSH), .git.
    $repo = ''
    if ($remote) {
      $url = Invoke-Git @('-C', $cwdRaw, 'remote', 'get-url', $remote)
      if ($url) {
        $repo = $url -replace '^[a-z]+://[^/]+/', '' -replace '^[^@]*@[^:/]+[:/]', '' -replace '\.git$', ''
      }
    }
    if ($repo) { $branchSegment = "$repo $alt $br" } else { $branchSegment = "$alt $br" }
  } else {
    $branchSegment = "$alt no git"
  }
}

# --- line 3: context window -------------------------------------------------
$usedPct    = $j.context_window.used_percentage
$totalInput = $j.context_window.total_input_tokens
$ctxSize    = $j.context_window.context_window_size

$ctxSegment = ''
if ($null -ne $usedPct) {
  $bar = Make-Bar $usedPct 14
  $ctxSegment = ('ctx [{0}] {1}%' -f $bar, [int][math]::Round([double]$usedPct))
  if ($totalInput -and $ctxSize) {
    $ctxSegment += '   ' + (Format-Tokens $totalInput) + '/' + (Format-Tokens $ctxSize)
  }
}

# --- line 4: usage — subscription windows OR billing mode + session cost -----
# `rate_limits` present  -> render the 5h/7d windows (subscription).
# Absent -> detect a non-subscription billing mode from the env the CLI exports
# (CLAUDE_CODE_OAUTH_TOKEN is deliberately NOT a signal — it is a subscription
# token and still yields rate_limits). With no env signal but cost > 0, render
# the bare cost detail (steady-state claude.ai enterprise). With cost 0 and no
# signal, stay silent (fresh subscription session — don't mislabel).
$fhPct   = $j.rate_limits.five_hour.used_percentage
$fhReset = $j.rate_limits.five_hour.resets_at
$sdPct   = $j.rate_limits.seven_day.used_percentage
$sdReset = $j.rate_limits.seven_day.resets_at

$winSegment = ''
if ($null -ne $fhPct -or $null -ne $sdPct) {
  if ($null -ne $fhPct) {
    $seg = ('5h:{0}%' -f [int][math]::Round([double]$fhPct))
    $r = Format-Reset $fhReset; if ($r) { $seg += " (resets $r)" }
    $winSegment = $seg
  }
  if ($null -ne $sdPct) {
    $seg = ('7d:{0}%' -f [int][math]::Round([double]$sdPct))
    $r = Format-Reset $sdReset; if ($r) { $seg += " (resets $r)" }
    if ($winSegment) { $winSegment += "   $seg" } else { $winSegment = $seg }
  }
} else {
  $mode = ''
  if     ($env:CLAUDE_CODE_USE_BEDROCK) { $mode = 'bedrock' }
  elseif ($env:CLAUDE_CODE_USE_VERTEX)  { $mode = 'vertex' }
  elseif ($env:CLAUDE_CODE_USE_FOUNDRY) { $mode = 'foundry' }
  elseif ($env:ANTHROPIC_API_KEY)       { $mode = 'api' }
  elseif ($env:ANTHROPIC_AUTH_TOKEN -or $env:ANTHROPIC_BASE_URL) { $mode = 'gateway' }

  # "session cost $X · duration Y" from the payload's cost block (CLI-computed,
  # so the total is authoritative; we don't recompute it).
  $mid = [string][char]0x00B7   # ·
  $costDetail = ''
  $cost = $j.cost.total_cost_usd
  if ($null -ne $cost -and [double]$cost -gt 0) {
    $costDetail = ('session cost ${0:0.00}' -f [double]$cost)
    $d = Format-Duration $j.cost.total_duration_ms
    if ($d) { $costDetail += " $mid duration $d" }
  }
  if ($mode) {
    $winSegment = $mode
    if ($costDetail) { $winSegment += "  $costDetail" }
  } elseif ($costDetail) {
    $winSegment = $costDetail
  }
}

# --- assemble (up to four lines; empty lines dropped) ------------------------
$line1 = $model
if ($cwd) { $line1 += "  $cwd" }

$lines = @($line1)
if ($branchSegment) { $lines += $branchSegment }
if ($ctxSegment)    { $lines += $ctxSegment }
if ($winSegment)    { $lines += $winSegment }

[Console]::Out.Write(($lines -join "`n"))
# Always succeed: a non-zero exit can make Claude Code suppress the status line.
exit 0
