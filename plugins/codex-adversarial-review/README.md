# codex-adversarial-review

A **methodology** for stress-testing substantive prose, claims, or code with an
adversarial second model (Codex) before finalising. Two structured rounds, with
the load-bearing work being *synthesis* — you decide what to adopt, reject, and
push back on; you never just relay the reviewer's output.

## What's in the box

| Path | What it is |
|---|---|
| `skills/codex-adversarial-review/SKILL.md` | The method: brief → attack → synthesise → re-attack → rule on pushbacks. |
| `skills/codex-adversarial-review/assets/round1_brief_template.md` | A fill-in brief template (role, artefact, context, numbered attack vectors, output format). |

## This is methodology, not tooling

It does not ship a Codex server. It assumes you already have one — typically the
[`codex@openai-codex`](https://github.com/openai/codex-plugin-cc) plugin exposing
`mcp__codex__codex` and `mcp__codex__codex-reply`, or a `codex` CLI. The value
here is *how* to run the review: what to put in the brief, how many rounds, and
how to turn the reviewer's critique into a defensible revision instead of a
copy-paste.

## The loop in one breath

1. **Round 1** — brief Codex with the artefact (line-numbered), the surrounding
   vocabulary/constraints it must respect, and a numbered list of attack vectors;
   ask for load-bearing-vs-nitpick verdicts plus concrete rewrites.
2. **Synthesise** — classify every point as Adopt / Reject / Pushback, produce v2
   and a short ledger.
3. **Round 2** — send v2 on the same thread with your pushbacks; ask Codex to
   re-attack *and* rule on the pushbacks. Synthesise into the final.
4. **Report** the v1 → final delta and the ledger — not the raw transcript.

Default to two rounds. More than two usually means the artefact needed more
thinking before round 1.

## Setup

```
/plugin install codex-adversarial-review@hanifz-claude-skills
# plus a Codex reviewer, e.g.:
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
```

## License

MIT. See the repository `LICENSE`.
