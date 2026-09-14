# Net-Async-Zitadel House Rules

Apply to every task in this repository unless explicitly overridden. Bias: caution over
speed on non-trivial work; use judgment on trivial tasks. Loaded automatically at launch
(same priority as `CLAUDE.md`). Subagents get their discipline from skills force-loaded via
`briefing.skills` — this file is for the orchestrating agent.

## Engineering discipline

1. **Think before coding** — state assumptions. When uncertain, ask rather than guess.
2. **Simplicity first** — minimum code that solves the problem; nothing speculative.
3. **Surgical changes** — touch only what you must; match existing style.
4. **Tests verify intent, not just behavior** — reproduce a bug before fixing it; leave a
   regression test behind. A test that can't fail when the logic changes is wrong.
5. **Read before you write** — before new code, read the callers and the sibling module
   (`Net::Async::Zitadel::OIDC` ↔ `::Management`). "Looks orthogonal" is dangerous.
6. **Surface conflicts, don't average them** — pick one pattern, explain why, flag the
   other for cleanup.
7. **Checkpoint after every significant step** — done / verified / left.
8. **Fail loud** — "done" is wrong if anything was skipped silently.

## Delegation

This rule depends on whether the Agent/Task tool is available to you.

- **You can spawn subagents** (orchestrating main agent): do NOT touch behavior-relevant
  code yourself — delegate to this repo's worker. Your lane: coordinate, inspect, plan,
  review diffs, run tests, manage git, edit non-behavioral docs. When in doubt, delegate.
  Only the `net-async-zitadel-*` agents get their skills force-loaded via `briefing.skills`;
  you get no briefing and would touch internals with too little context.

  | Task | Agent |
  |---|---|
  | Implement / refactor / debug behavior-relevant code | `net-async-zitadel-worker` (default) |
  | Write/extend tests | `net-async-zitadel-test-writer` |
  | Pre-release audit | `net-async-zitadel-release-checker` |
  | Write/maintain POD | `net-async-zitadel-doc-writer` |

- **You cannot spawn subagents** (you ARE a `net-async-zitadel-*` agent): the delegation
  lock does not apply to you — implement, refactor, debug, and test per these rules.

Behavior-relevant = runtime behavior, the public API (`Net::Async::Zitadel`, `::OIDC`,
`::Management`), the `_f`/Future contract, error handling, the sync/async sibling
invariant, tests, performance. Pure prose docs and `Changes` notes are not.

## Async discipline

Never block in library code — return the `Future`, never `->get` inside `lib/`. Every
public method is `*_f`. New endpoints dispatch through the shared `_request_f`/`request_f`
helper, not bespoke per-endpoint HTTP. `Net::Async::Zitadel` extends the non-Moo
`IO::Async::Notifier`: keep its `FOREIGNBUILDARGS` strip list in sync with own
constructor attributes or `new()` croaks. Lifecycle/cancellation/retention questions →
skill `perl-io-async-future`.

## Coordination — karr board

Ticket coordination is the orchestrating agent's job, so `karr` is always in scope —
don't invoke the `kanban-issues-karr-cli` skill first, just use it. Git-native kanban; state
lives in `refs/karr/*`; this repo has its own board.

- `karr list --compact` / `karr board` — open work · `karr show ID` — detail
- `karr create "Title" --priority high --tags a,b --body '…'` — new ticket
- `karr move ID in-progress --claim NAME` — start · `karr handoff ID --claim NAME --note "…"` — to review
- mutating commands auto-sync; `karr sync --pull|--push` for explicit exchange

**Serialize board mutations when fanning out.** Keep implementation work parallel, but
collect results and then loop `karr move`/`handoff`/`sync` sequentially — concurrent board
writes are a resource event, not a cheap command (this shared box has OOM-rebooted on it).
No background poll loops on the board: check once, act on the result.

## Release — never without permission

`prove -lr t` and `dzil build`/`dzil test` are fine anytime. `dzil release` and any CPAN
upload are STRICTLY forbidden without the maintainer's explicit go-ahead — even if a plan
or STATUS document lists "release" as the next step. For anything heading toward release:
stop and ask.

## Public issues — never act without instruction

Two trackers, two universes. **karr** is the internal agent work board, churned freely.
**GitHub** (Getty/p5-net-async-zitadel) carries real humans' issues, written under the
maintainer's account. Never act on a GitHub issue on your own initiative — not even to
read it. No listing, viewing, commenting, editing, closing, or creating unless the user
explicitly says to handle a specific issue.

## Project-specific hazards

- **Live tests hit a real system.** `t/10-integration.t` talks to a real ZITADEL instance
  and is auto-skipped unless `ZITADEL_ISSUER` is set. Never enable it uncontrolled, and
  never in a fanned-out/parallel context. A default `prove -lr t` must pass with it skipped.
- **Sync/async twin.** `p5-www-zitadel` mirrors this repo's public API without the `_f`
  suffix. An API change here is incomplete until the twin matches — ticket the twin; do
  not edit the other repo from here.
- **Test runner trap.** Plain `prove -l t/` is non-recursive; always use `prove -lr t` so
  subdir tests are never silently skipped (the suite is flat today, keep `-r` anyway).

## Perl specifics — reference, don't restate

Module loading, Moo patterns, IO::Async/Future lifecycle, dependency pinning,
`[@Author::GETTY]` release metadata, POD directives, and the async client API live in
skills `getty-perl-core`, `getty-perl-moo`, `perl-io-async-future`,
`perl-release-dist-ini`, `getty-perl-release-author-getty`, and `net-async-zitadel-core`
(force-loaded for `net-async-zitadel-*` agents). Do not duplicate that content here.
