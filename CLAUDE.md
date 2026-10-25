# CLAUDE.md

Repo guide for `Net::Async::Zitadel`. The general Perl rules (module loading,
Moo/Moose, `[@Author::GETTY]` Dist::Zilla, cpanfile versioning, style) live in the
workspace `../CLAUDE.md` and in the `getty-perl-core` skill — they still apply here.

## What is this?

IO::Async-based client for the [Zitadel](https://zitadel.com) admin and auth API.
One class per concern (`::OIDC` for token verification/userinfo, `::Management` for
the admin API), a shared error hierarchy under `::Error`.

## Layout

- `lib/Net/Async/Zitadel.pm` — main docs + shared constructor logic
- `lib/Net/Async/Zitadel/OIDC.pm` — OIDC: discovery, JWKS, token, userinfo, introspect
- `lib/Net/Async/Zitadel/Management.pm` — admin API: users, apps, projects, orgs, IDPs, …
- `lib/Net/Async/Zitadel/Error.pm` — `::Validation`, `::Network`, `::API` (with `http_status`, `api_message`)
- `examples/verify_token.pl`, `client_credentials.pl`, `manage_users.pl` — runnable scripts
- `t/10-integration.t` — live integration tests, skipped without `ZITADEL_ISSUER`

## Build & test

```bash
dzil test                      # full Dist::Zilla test suite
prove -lr t/                   # everything (recursive!)
prove -lv t/02-oidc.t          # a single test
cpanm --installdeps .          # deps from cpanfile
dzil release                   # CPAN release via [@Author::GETTY]
```

Live integration tests are **skipped automatically** when `ZITADEL_ISSUER` is not
set — no secret leaks in CI.

## Async conventions

IO::Async + Future/Future::AsyncAwait. Lifecycle, cancellation or retention
questions → skill `perl-io-async-future`. Moo attributes, roles, `->instance`
semantics → skill `getty-perl-moo`.

## Error handling

Every API endpoint throws a `Net::Async::Zitadel::Error::*` subclass: `::Network` for
network failures, `::API` for HTTP 4xx/5xx with API detail (with `http_status` and
`api_message`), `::Validation` for local constructor validation.

Example:

```perl
try {
    my $info = await $zitadel->oidc->userinfo_f($token);
} catch ($e) where { $_->isa('Net::Async::Zitadel::Error::API') && $_->http_status == 401 } {
    # token invalid
}
```

## Adding an endpoint

1. A `*_f` method (returns a `Future`, never blocks) in the matching client module
   (`OIDC.pm` for auth, `Management.pm` for admin).
2. Dispatch through the shared `request_f` helper — no per-endpoint HTTP logic.
3. A test in `t/` with a mocked response; a live call following the pattern in
   `t/10-integration.t`.
4. Document the new endpoint in `Changes` under `{{$NEXT}}`.

## Delegation

Delegate behavior-relevant code to the right agent instead of touching it yourself —
the delegation lock is a shared house rule (skilletor bundle `getty-cpan-dist@getty`);
lanes and hazards are in `.claude/rules/net-async-zitadel-rules.md`.

| Task | Agent |
|---|---|
| Implement / refactor / debug code | `net-async-zitadel-worker` (default) |
| Write/extend tests | `net-async-zitadel-test-writer` |
| Write/maintain POD | `net-async-zitadel-doc-writer` |
| Pre-release audit | `net-async-zitadel-release-manager` |

The agents load their skills via `briefing.skills` (see `.claude/agents/`); the main
agent delegates instead of loading them itself. Skill sources live under
`.claude/skills/`. Twin: `p5-www-zitadel` (sync, identical API without `_f`).
