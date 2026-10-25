# Net-Async-Zitadel House Rules

The shared house rules come from skilletor — bundle `getty-cpan-dist@getty`: engineering
discipline, the delegation lock, the publish gate, karr coordination, CPAN release. They load
as `.claude/rules/.local.*.md`; if they are missing, run `skilletor sync` and publish nothing
until they load. This file adds what is true only here, and wins where it differs.

## What this repo is

Async Perl client for Zitadel identity management (IO::Async + Future). Read first: the
callers and the sibling module (`Net::Async::Zitadel::OIDC` ↔ `::Management`).

## Agent team

| Task | Agent |
|---|---|
| Implement / refactor / debug behavior-relevant code | `net-async-zitadel-worker` (default) |
| Write/extend tests | `net-async-zitadel-test-writer` |
| Write/maintain POD | `net-async-zitadel-doc-writer` |
| Commits, `Changes`, card → done, pre-release audit | `net-async-zitadel-release-manager` |
| Read-only research, audit, gap analysis | `net-async-zitadel-worker` ("read-only, change nothing") |

Behavior-relevant = runtime behavior, the public API (`Net::Async::Zitadel`, `::OIDC`,
`::Management`), the `_f`/Future contract, error handling, the sync/async sibling invariant,
tests, performance. Pure prose docs and `Changes` notes are not.

## Hazards

- **Never block in library code** — return the `Future`, never `->get` inside `lib/`. New
  endpoints dispatch through the shared `_request_f`/`request_f` helper, not bespoke
  per-endpoint HTTP.
- **Live tests hit a real system.** `t/10-integration.t` talks to a real ZITADEL instance and
  is auto-skipped unless `ZITADEL_ISSUER` is set. Never enable it uncontrolled, and never in a
  fanned-out/parallel context. A default `prove -lr t` must pass with it skipped.
- **Sync/async twin.** `p5-www-zitadel` mirrors this repo's public API without the `_f`
  suffix. An API change here is incomplete until the twin matches — ticket the twin; do not
  edit the other repo from here.
- **Test runner trap.** Plain `prove -l t/` is non-recursive; always use `prove -lr t` so
  subdir tests are never silently skipped (the suite is flat today, keep `-r` anyway).

## Perl specifics — reference, don't restate

Module loading, Moo patterns, IO::Async/Future lifecycle, dependency pinning,
`[@Author::GETTY]` release metadata, POD directives and the async client API live in skills
`getty-perl-core`, `getty-perl-moo`, `perl-io-async-future`, `perl-release-dist-ini`,
`getty-perl-release-author-getty` and `net-async-zitadel-core` (force-loaded for
`net-async-zitadel-*` agents).
