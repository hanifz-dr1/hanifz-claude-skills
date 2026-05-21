---
name: codex-adversarial-review
description: Use this skill when the user wants a substantive artefact stress-tested by an adversarial second model before finalising — e.g. "have Codex attack this", "red-team this claim/argument", "get an adversarial review of this section/PR", "find the weaknesses in this draft". It runs a two-round structured loop with a Codex MCP/CLI. Round 1 briefs the model with the artefact + surrounding vocabulary + a numbered attack-vector list and asks for load-bearing-vs-nitpick verdicts and concrete rewrites; you synthesise v2 with explicit adopt/reject/pushback; round 2 re-attacks v2 and rules on the pushbacks. Skip for typos and mechanical edits.
version: 0.1.0
---

# codex-adversarial-review — two-round adversarial stress test

## Purpose

Substantive outputs (claim drafts, novelty/argument paragraphs, prior-art
contrasts, design rationale, tricky code) get sharper when a *different* model
tries to break them. This skill is the **methodology** for doing that well with
a Codex MCP/CLI: how to brief, how many rounds, and — most importantly — how to
**synthesise rather than relay** the reviewer's output.

The default is **two sequential rounds**. More than two usually means the
artefact needed more thinking before round 1, not more rounds.

## Preconditions

- A Codex reviewer is reachable. Typical setup is the `codex@openai-codex`
  plugin exposing `mcp__codex__codex` (initial brief) and `mcp__codex__codex-reply`
  (follow-up on the same thread). If those tools aren't loaded, fetch via
  `ToolSearch "select:mcp__codex__codex,mcp__codex__codex-reply"`. A `codex` CLI
  works too; the methodology is tool-agnostic.
- Suggested invocation for an adversarial pass: a capable model at high reasoning
  effort, **read-only sandbox**, no auto-approval, `cwd` set to the repo so the
  reviewer can read referenced files.

## When NOT to use

- Typos, formatting, renames, mechanical refactors — just do them.
- Artefacts you haven't drafted yet. Review sharpens a draft; it doesn't write one.

## Round 1 — brief and attack

1. **Assemble the brief** (use `assets/round1_brief_template.md`):
   - The artefact, verbatim, with line numbers if it lives in a file (so the
     reviewer can cite precisely). If the reviewer's sandbox can't read files,
     paste the line-numbered excerpt directly.
   - **Surrounding vocabulary / constraints** the reviewer needs to judge fairly:
     domain terms, the claim taxonomy, naming conventions, house style rules
     (e.g. "no em dashes"), cross-reference conventions. Without this the reviewer
     invents objections that violate constraints it didn't know about.
   - A **numbered list of attack vectors** tailored to the artefact. Generic set
     to specialise:
     1. Claim alignment — does the text match what's actually claimed/built?
     2. Scope / over-breadth / over-narrowness.
     3. Terminology drift / inconsistent vocabulary.
     4. Internal contradiction or unsupported assertion.
     5. Missing prior art / counterexample / failure mode.
     6. House-style violations (punctuation, cross-refs, structure).
   - The **ask**: terse, load-bearing-vs-nitpick verdict per issue, plus a
     concrete rewrite for each load-bearing one. Discourage vague critique.
2. **Send** via `mcp__codex__codex`. Keep the returned `threadId` — round 2 needs it.

## Synthesis (the load-bearing step)

**Do not relay Codex's output to the user.** Read every point and classify:

| Disposition | Meaning | Action |
|---|---|---|
| **Adopt** | Correct and load-bearing | Apply the fix to v2. |
| **Reject** | Wrong, or based on a constraint Codex missed | Drop it; note why in one line. |
| **Pushback** | Partially right, or right premise / wrong fix | Apply your own fix AND flag it for round 2 to rule on. |

Produce **v2** of the artefact plus a short adopt/reject/pushback ledger. The
ledger is what makes round 2 productive and what you show the user.

## Round 2 — re-attack and rule on pushbacks

1. Send v2 via `mcp__codex__codex-reply` (round 1's `threadId`) with:
   - the revised artefact,
   - your **pushback list** (each: "you said X; I kept Y because Z — is Z sound?"),
   - the ask: attack the revision afresh **and** rule on each pushback.
2. Synthesise again into the final version. Resolve pushbacks explicitly: either
   the reviewer conceded, or it held its ground with a reason you now adopt or
   over-rule (state which).

## After

- Report to the user: what changed between v1 → final, the adopt/reject/pushback
  ledger, and any disagreement you over-ruled (with your reason). This is the
  audit trail; the raw Codex transcript is not.
- If round 2 surfaced a *new* substantive problem (not a refinement), that's a
  signal the artefact's structure is unsettled — consider one more round only if
  the new issue is genuinely load-bearing; otherwise note it and stop.

## Anti-patterns

- **Relaying instead of synthesising** — pasting Codex's list to the user abdicates
  the judgement that is the whole point. Always classify and decide.
- **Briefing without vocabulary** — the reviewer then objects to things the
  conventions already settle, wasting a round.
- **Unbounded rounds** — past two, diagnose the artefact, don't keep asking.
- **Accepting fluent-but-wrong rewrites** — a confident rewrite that violates a
  constraint is a Reject, not an Adopt. Ground every adopted change against the
  source/spec, not against the reviewer's confidence.
- **Reviewing trivia** — spending an adversarial round on formatting.
