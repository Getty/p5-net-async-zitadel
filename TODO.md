# TODO - Net::Async::Zitadel

## OIDC Implementation

- [x] Implement `introspect_f` — POST form-encoded to introspection endpoint via Net::Async::HTTP
- [x] Implement `token_f` — POST form-encoded to token endpoint via Net::Async::HTTP
- [x] `client_credentials_token_f`, `refresh_token_f`, `exchange_authorization_code_f` depend on `token_f`
- [x] Discovery caching with TTL (discovery_ttl attr, default 3600s)
- [x] JWKS caching with TTL (jwks_ttl attr, default 300s)

## Management API

- [x] All Management methods implemented and functional (using `_request_f`)
- [x] Error handling uses `Net::Async::Zitadel::Error` typed exceptions, matching WWW::Zitadel behavior
- [x] Missing endpoints from initial impl added: service users, machine keys, password,
      metadata, org operations (create/list/update/deactivate), update_oidc_app camelCase fix
- [x] `BUILD` validation for empty `base_url` and `issuer`

## Test Suite

- [x] Unit tests for OIDC discovery/JWKS caching (mock HTTP responses, t/02-oidc.t)
- [x] Unit tests for token verification with JWKS retry (mock decoder)
- [x] Unit tests for Management API methods — paths, payload shapes, validation (t/03-management.t)
- [x] Integration tests against a live Zitadel instance (behind env guard, t/10-integration.t)
- [x] Test Future failure paths (HTTP errors, JSON parse errors, missing fields)
- [x] Network timeout: pending Future stays non-ready without premature exception (t/02-oidc.t)
- [x] Concurrent JWKS refresh coalescing — race condition prevention (t/02-oidc.t)
- [x] In-flight slot cleared correctly after synchronous failure

## Documentation

- [x] POD for all public methods with SYNOPSIS and DESCRIPTION
- [x] Cookbook/examples directory

## Examples

- [x] `examples/verify_token.pl` — simple token verification in an IO::Async loop
- [x] `examples/manage_users.pl` — CRUD users asynchronously
- [x] `examples/client_credentials.pl` — obtain tokens via client credentials

## Integration with HI

- [ ] Use in HI::Role::Caste agents for async Zitadel auth
- [ ] Replace synchronous WWW::Zitadel calls in Beekeeper/Propolis with async versions
- [ ] Tenant provisioning via async Management API

## CPAN Release

- [x] First pass of `dzil test`
- [x] Verify dist builds cleanly with `dzil build`
- [ ] Release to CPAN
