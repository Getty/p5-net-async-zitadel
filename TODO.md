# TODO - Net::Async::Zitadel

## OIDC Implementation

- [ ] Implement `introspect_f` — POST form-encoded to introspection endpoint via Net::Async::HTTP
- [ ] Implement `token_f` — POST form-encoded to token endpoint via Net::Async::HTTP
- [ ] `client_credentials_token_f`, `refresh_token_f`, `exchange_authorization_code_f` depend on `token_f`
- [ ] Discovery caching with TTL (currently cached forever)
- [ ] JWKS caching with TTL

## Management API

- [ ] All Management methods are implemented and functional (they use `_request_f` which is complete)
- [ ] Verify error handling matches WWW::Zitadel behavior

## Test Suite

- [ ] Unit tests for OIDC discovery/JWKS (mock HTTP responses)
- [ ] Unit tests for token verification (use test JWTs)
- [ ] Unit tests for Management API methods (mock HTTP responses)
- [ ] Integration tests against a live Zitadel instance (behind env guard)
- [ ] Test Future failure paths (HTTP errors, JSON parse errors, missing fields)

## Documentation

- [ ] POD for all public methods (skeletons in place)
- [ ] SYNOPSIS examples for each module
- [ ] Cookbook/examples directory

## Examples

- [ ] `examples/verify_token.pl` — simple token verification in an IO::Async loop
- [ ] `examples/manage_users.pl` — CRUD users asynchronously
- [ ] `examples/client_credentials.pl` — obtain tokens via client credentials

## Integration with HI

- [ ] Use in HI::Role::Caste agents for async Zitadel auth
- [ ] Replace synchronous WWW::Zitadel calls in Beekeeper/Propolis with async versions
- [ ] Tenant provisioning via async Management API

## CPAN Release

- [ ] First pass of `dzil test`
- [ ] Verify dist builds cleanly with `dzil build`
- [ ] Release to CPAN
