---
name: net-async-zitadel-core
description: Use when talking to ZITADEL from async Perl — Net::Async::Zitadel (IO::Async + Future), the _f OIDC and Management API, error handling, and its tests.
user-invocable: true
allowed-tools: Read, Grep, Glob, Bash
model: sonnet
---

Use this skill when the task is "how do I use or maintain `Net::Async::Zitadel`?".
This is the async twin of `WWW::Zitadel` (`p5-www-zitadel/`): **identical public
API surface, every call suffixed `_f` and returning a `Future`** instead of a
blocking result.

## The delegation model — why the main agent delegates

Four roles: `net-async-zitadel-worker` (implement, refactor, debug),
`net-async-zitadel-test-writer` (tests), `net-async-zitadel-release-manager` (commit,
`Changes`, card → done, pre-release audit), `net-async-zitadel-doc-writer` (POD). All
four get their skills force-loaded via `briefing.skills`. The orchestrating main agent gets
**no briefing** — it coordinates, inspects, plans, reviews diffs, runs tests and edits
non-behavioral docs, and delegates anything behavior-relevant here. Reason: only the
briefed agents see the sync/async twin invariant and the `_f` contract in context; an
unbriefed hand inside `lib/` would break exactly those. When in doubt, delegate.

Behavior-relevant = runtime behavior, the public API (`Net::Async::Zitadel`, `::OIDC`,
`::Management`), the `_f`/Future contract, error handling, the sync/async sibling invariant,
tests, performance. Pure prose docs and `Changes` notes are not.

## Async discipline

- **Never block in library code** — return the `Future`, never `->get` inside `lib/`.
- Every public method is `*_f`; new endpoints dispatch through the shared
  `_request_f`/`request_f` helper, not bespoke per-endpoint HTTP.
- `Net::Async::Zitadel` extends the **non-Moo** `IO::Async::Notifier`: keep its
  `FOREIGNBUILDARGS` strip list in sync with its own constructor attributes, or `new()`
  croaks on an unknown key.
- Lifecycle, cancellation and retention questions → skill `perl-io-async-future`.

## Module map

- `Net::Async::Zitadel`: unified entrypoint; an `IO::Async::Notifier`. Attrs
  `issuer` (required), `token` (optional, only for Management), lazy `http`,
  lazy `oidc`, lazy `management`. Add it to a loop (`$loop->add($z)`); it owns a
  shared `Net::Async::HTTP` child that `oidc`/`management` reuse.
- `Net::Async::Zitadel::OIDC`: discovery, JWKS, token verify, userinfo,
  introspection, token-endpoint helpers — all `*_f`.
- `Net::Async::Zitadel::Management`: Management API v1 (users/service-users/
  machine-keys/metadata/projects/apps/orgs/roles/grants/IDPs) — all `*_f`,
  dispatched through the shared `_request_f`/`_get_f`/`_post_f`/`_put_f`/`_delete_f`.
- `Net::Async::Zitadel::Error`: exception base; subclasses `::Validation`,
  `::Network`, `::API`. Objects overload `""` to `message`, so string matching on
  a rejected Future still works.

## Quickstart

```perl
use IO::Async::Loop;
use Net::Async::Zitadel;

my $loop = IO::Async::Loop->new;
my $z = Net::Async::Zitadel->new(
    issuer => 'https://zitadel.example.com',
    token  => $ENV{ZITADEL_PAT},   # only needed for management calls
);
$loop->add($z);

my $claims   = $z->oidc->verify_token_f($jwt, audience => 'client-id')->get;
my $projects = $z->management->list_projects_f(limit => 20)->get;
```

Management methods are direct (`list_users_f`, `create_human_user_f`,
`create_project_f`) — there is no `->users->list` subclient API.

## OIDC usage (all `_f`)

`discovery_f`, `jwks_f(force_refresh => 1?)`, `verify_token_f($jwt, audience =>
…, verify_exp => 1, …, no_retry => 1?)`, `userinfo_f($access_token)`,
`introspect_f($token, client_id => …, client_secret => …)`,
`token_f(grant_type => …, …)`, and the wrappers `client_credentials_token_f`,
`refresh_token_f`, `exchange_authorization_code_f`.

`verify_token_f` retries **once** with a force-refreshed JWKS when signature
validation fails (key rotation), unless `no_retry`. Discovery is cached
`discovery_ttl` (3600s), JWKS `jwks_ttl` (300s). Concurrent non-forced
`jwks_f` calls **coalesce** onto one in-flight Future (`_jwks_inflight`) so a
burst issues a single HTTP fetch.

## Management usage (all `_f`)

```perl
my $mgmt = Net::Async::Zitadel::Management->new(
    base_url => 'https://zitadel.example.com',
    token    => $ENV{ZITADEL_PAT},
    http     => $shared_http,   # normally handed down by Net::Async::Zitadel
);
```

Typical flow: `create_project_f` → `create_oidc_app_f($project_id, …)` →
`add_project_role_f($project_id, role_key => …)` → `create_user_grant_f(user_id
=> …, project_id => …, role_keys => […])`.

## Error handling

Every endpoint rejects its Future with a typed exception:

- `::Validation` — bad/missing args *before* any HTTP call (empty issuer,
  missing token/client_id, …). Thrown synchronously as a failed Future.
- `::Network` — OIDC endpoint HTTP failure (discovery/JWKS/userinfo/token non-2xx).
- `::API` — Management API non-2xx; carries `http_status` (e.g. `"404 Not Found"`)
  and `api_message` (from the JSON body).

```perl
$z->oidc->userinfo_f($token)->catch(sub {
    my ($err) = @_;
    if (ref $err && $err->isa('Net::Async::Zitadel::Error::API')) {
        warn 'HTTP ', $err->http_status, ': ', $err->api_message;
    }
    return Future->fail($err);   # re-raise
});
```

## Invariants to keep

- **Never block in library code.** No `->get` inside `lib/` — return the Future.
  `->get` belongs only in synchronous callers/examples/tests.
- **`FOREIGNBUILDARGS` trap.** `Net::Async::Zitadel` extends the non-Moo
  `IO::Async::Notifier`, whose `new()` forwards every key to `configure()` and
  croaks on unknown ones. `FOREIGNBUILDARGS` strips `issuer`/`token`/`http`
  before they reach the parent — add any new own constructor attribute to that
  strip list or construction breaks.
- **One shared `http`.** `oidc` and `management` receive the parent's
  `Net::Async::HTTP` child; don't spin up per-client HTTP.
- **`_request_f` is the single dispatch path** in Management — new endpoints go
  through it, not bespoke per-method HTTP.
- **Sync/async twin.** A public-API change in `WWW::Zitadel::{Management,OIDC}`
  is only half done until the matching `*_f` lands here (and vice versa).

## Adding an endpoint

1. Add the method as `*_f` (returns a `Future`, never blocks) in `OIDC.pm`
   (auth) or `Management.pm` (admin).
2. Dispatch via the shared `request_f`/`_request_f` helper — no per-endpoint HTTP.
3. Add a mocked-response test in `t/` (pattern: `t/02-oidc.t` / `t/03-management.t`);
   live calls follow `t/10-integration.t`.
4. Note it under `{{$NEXT}}` in `Changes`.

## Test commands

```bash
prove -lr t                    # recursive; offline, live suite auto-skips
prove -lv t/03-management.t    # one file
```

`t/10-integration.t` talks to a real ZITADEL and is **auto-skipped unless
`ZITADEL_ISSUER` is set** — never enable it in a fanned-out/parallel context.
A default `prove -lr t` must pass with it skipped.
