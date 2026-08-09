# CLAUDE.md

Repo-Guide für `Net::Async::Zitadel`. Die allgemeinen Perl-Regeln (Module-Loading,
Moo/Moose, `@Author::GETTY]` Dist::Zilla, cpanfile-Versionierung, Style) stehen
in der Workspace-`../CLAUDE.md` und im `perl-core`-Skill — die gelten hier
weiterhin.

## Was ist das?

IO::Async-basierter Client für die [Zitadel](https://zitadel.com) Admin- und
Auth-API. Eine Klasse pro Concern (`::OIDC` für Token-Verifikation/Userinfo,
`::Management` für die Admin-API), geteilte Fehlerhierarchie unter `::Error`.

## Layout

- `lib/Net/Async/Zitadel.pm` — Hauptdoku + gemeinsame Konstruktor-Logik
- `lib/Net/Async/Zitadel/OIDC.pm` — OIDC: Discovery, JWKS, Token, Userinfo, Introspect
- `lib/Net/Async/Zitadel/Management.pm` — Admin-API: User, Apps, Projekte, Orgs, IDPs, …
- `lib/Net/Async/Zitadel/Error.pm` — `::Validation`, `::Network`, `::API` (mit `http_status`, `api_message`)
- `examples/verify_token.pl`, `client_credentials.pl`, `manage_users.pl` — lauffähige Skripte
- `t/10-integration.t` — Live-Integrationstests, übersprungen ohne `ZITADEL_ISSUER`

## Build & Test

```bash
dzil test                      # volle Dist::Zilla Testsuite
prove -lr t/                   # alles (rekursiv!)
prove -lv t/02-oidc.t          # einzelner Test
cpanm --installdeps .          # Deps aus cpanfile
dzil release                   # CPAN-Release via [@Author::GETTY]
```

Live-Integrationstests werden **automatisch übersprungen**, wenn `ZITADEL_ISSUER`
nicht gesetzt ist — kein Geheimnis-Leak in CI.

## Async-Konventionen

IO::Async + Future/Future::AsyncAwait. Bei Lifecycle-, Cancellation- oder
Retention-Fragen → Skill `perl-io-async-future`. Bei Moo-Attributen, Rollen,
`->instance`-Semantik → Skill `perl-moo`.

## Fehlerbehandlung

Jeder API-Endpunkt wirft eine `Net::Async::Zitadel::Error::*`-Subklasse. Bei
Netzwerkfehlern `::Network`, bei HTTP 4xx/5xx mit API-Detail `::API` (mit
`http_status` und `api_message`), bei lokalen Konstruktor-Validierungen `::Validation`.

Beispiel:

```perl
try {
    my $info = await $zitadel->oidc->userinfo_f($token);
} catch ($e) where { $_->isa('Net::Async::Zitadel::Error::API') && $_->http_status == 401 } {
    # Token ungültig
}
```

## Neuen Endpunkt hinzufügen

1. Methode als `*_f` (gibt `Future` zurück, nie blockierend) im passenden
   Client-Modul (`OIDC.pm` für Auth, `Management.pm` für Admin).
2. Über die geteilte `request_f`-Helper-Funktion dispatchen — keine eigene
   HTTP-Logik pro Endpoint.
3. Test in `t/` mit gemockter Response; Live-Call nach dem Muster in
   `t/10-integration.t`.
4. Neuen Endpunkt in `Changes` unter `{{$NEXT}}` dokumentieren.
