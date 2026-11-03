#!/usr/bin/env perl
use strict;
use warnings;

use Test::More;
use Test::Exception;
use JSON::MaybeXS;
use Future;
use MIME::Base64 qw(decode_base64);

use Net::Async::Zitadel::Management;
use Net::Async::Zitadel::Error;

# Mirrors WWW-Zitadel 0.002 t/03-management.t coverage for the async `_f`
# variants of the 28 Management methods added in this release. Uses the same
# short-circuiting Recorder pattern as t/03-management.t: _request_f is
# replaced with one that records [method, path, body] and returns a resolved
# Future, so we assert HTTP method, exact path, and JSON payload shape without
# any network I/O. Required-arg validation dies synchronously (before any
# request is made), so throws_ok exercises it directly.

{
    package Local::Recorder;
    use Moo;
    extends 'Net::Async::Zitadel::Management';

    has calls => (is => 'rw', default => sub { [] });

    sub _request_f {
        my ($self, $method, $path, $body) = @_;
        push @{ $self->calls }, [$method, $path, $body];
        return Future->done({ ok => JSON::MaybeXS::true });
    }
}

sub _recorder {
    Local::Recorder->new(
        base_url => 'https://zitadel.example.com',
        token    => 'pat-token',
        http     => bless({}, 'Local::FakeHTTP'),
    );
}

# --- User grant lifecycle: update / deactivate / reactivate / delete ---

{
    my $m = _recorder();

    $m->update_user_grant_f('u1', 'g1', role_keys => ['admin']);
    $m->deactivate_user_grant_f('u1', 'g1');
    $m->reactivate_user_grant_f('u1', 'g1');
    $m->delete_user_grant_f('u1', 'g1');

    my $c = $m->calls;

    is $c->[0][0], 'PUT', 'update_user_grant_f uses PUT';
    is $c->[0][1], '/users/u1/grants/g1', 'update_user_grant_f path';
    is_deeply $c->[0][2]{roleKeys}, ['admin'], 'update_user_grant_f role_keys -> roleKeys';

    is_deeply $c->[1], ['POST', '/users/u1/grants/g1/_deactivate', {}],
        'deactivate_user_grant_f path';
    is_deeply $c->[2], ['POST', '/users/u1/grants/g1/_reactivate', {}],
        'reactivate_user_grant_f path';
    is_deeply $c->[3], ['DELETE', '/users/u1/grants/g1', undef],
        'delete_user_grant_f path';

    throws_ok { $m->update_user_grant_f(undef, 'g1', role_keys => ['admin']) }
        qr/user_id required/, 'update_user_grant_f validates user_id';
    throws_ok { $m->update_user_grant_f('u1', undef, role_keys => ['admin']) }
        qr/grant_id required/, 'update_user_grant_f validates grant_id';
    throws_ok { $m->deactivate_user_grant_f(undef, 'g1') }
        qr/user_id required/, 'deactivate_user_grant_f validates user_id';
    throws_ok { $m->reactivate_user_grant_f('u1', undef) }
        qr/grant_id required/, 'reactivate_user_grant_f validates grant_id';
    throws_ok { $m->delete_user_grant_f('u1', undef) }
        qr/grant_id required/, 'delete_user_grant_f validates grant_id';
}

# --- Typed identity providers (Add*Provider endpoints; providerOptions nested) ---

{
    my $m = _recorder();

    $m->create_jwt_idp_f(
        name             => 'J',
        issuer           => 'https://i',
        jwt_endpoint     => 'https://j',
        keys_endpoint    => 'https://k',
        header_name      => 'x',
        audience         => 'a',
        provider_options => { isCreationAllowed => JSON::MaybeXS::true },
    );
    $m->create_google_idp_f(
        name             => 'G',
        client_id        => 'c',
        client_secret    => 's',
        provider_options => { isAutoCreation => JSON::MaybeXS::true },
    );
    $m->create_azuread_idp_f(
        name          => 'A',
        client_id     => 'c',
        client_secret => 's',
        tenant        => 'tid',
    );
    $m->create_github_idp_f(
        name          => 'GH',
        client_id     => 'c',
        client_secret => 's',
    );
    $m->create_github_enterprise_idp_f(
        name                   => 'GHE',
        client_id              => 'c',
        client_secret          => 's',
        authorization_endpoint => 'https://a',
        token_endpoint         => 'https://t',
        user_endpoint          => 'https://u',
    );
    $m->create_gitlab_idp_f(
        name          => 'GL',
        client_id     => 'c',
        client_secret => 's',
    );
    $m->create_gitlab_self_hosted_idp_f(
        name          => 'GLS',
        issuer        => 'https://gl',
        client_id     => 'c',
        client_secret => 's',
    );
    $m->create_apple_idp_f(
        name        => 'AP',
        client_id   => 'c',
        team_id     => 't',
        key_id      => 'k',
        private_key => 'PK',
        scopes      => ['email'],
    );
    $m->create_ldap_idp_f(
        name                => 'L',
        servers             => ['ldap://x'],
        start_tls           => 1,
        base_dn             => 'dc=x',
        bind_dn             => 'cn=y',
        bind_password       => 'p',
        user_base           => 'ou=users',
        user_object_classes => ['person'],
        user_filters        => ['cn'],
        timeout             => 5,
        root_ca             => 'PEM',
    );

    my $c = $m->calls;

    # JWT
    is $c->[0][0], 'POST', 'create_jwt_idp_f uses POST';
    is $c->[0][1], '/idps/generic_jwt', 'create_jwt_idp_f path';
    is $c->[0][2]{name}, 'J', 'create_jwt_idp_f name';
    is $c->[0][2]{issuer}, 'https://i', 'create_jwt_idp_f issuer';
    is $c->[0][2]{jwtEndpoint}, 'https://j', 'create_jwt_idp_f jwt_endpoint -> jwtEndpoint';
    is $c->[0][2]{keysEndpoint}, 'https://k', 'create_jwt_idp_f keys_endpoint -> keysEndpoint';
    is $c->[0][2]{headerName}, 'x', 'create_jwt_idp_f header_name -> headerName';
    is $c->[0][2]{audience}, 'a', 'create_jwt_idp_f audience forwarded';
    ok $c->[0][2]{providerOptions}{isCreationAllowed}, 'create_jwt_idp_f provider_options nested';

    # Google
    is $c->[1][1], '/idps/google', 'create_google_idp_f path';
    is $c->[1][2]{name}, 'G', 'create_google_idp_f name forwarded';
    is $c->[1][2]{clientId}, 'c', 'create_google_idp_f client_id -> clientId';
    is $c->[1][2]{clientSecret}, 's', 'create_google_idp_f client_secret -> clientSecret';
    ok $c->[1][2]{providerOptions}{isAutoCreation}, 'create_google_idp_f provider_options nested';

    # AzureAD
    is $c->[2][1], '/idps/azure', 'create_azuread_idp_f path';
    is $c->[2][2]{name}, 'A', 'create_azuread_idp_f name';
    is $c->[2][2]{clientId}, 'c', 'create_azuread_idp_f client_id -> clientId';
    is $c->[2][2]{clientSecret}, 's', 'create_azuread_idp_f client_secret -> clientSecret';
    is $c->[2][2]{tenant}, 'tid', 'create_azuread_idp_f tenant passthrough';

    # GitHub
    is $c->[3][1], '/idps/github', 'create_github_idp_f path';
    is $c->[3][2]{name}, 'GH', 'create_github_idp_f name forwarded';
    is $c->[3][2]{clientId}, 'c', 'create_github_idp_f client_id -> clientId';

    # GitHub Enterprise
    is $c->[4][1], '/idps/github_es', 'create_github_enterprise_idp_f path';
    is $c->[4][2]{name}, 'GHE', 'create_github_enterprise_idp_f name';
    is $c->[4][2]{clientId}, 'c', 'create_github_enterprise_idp_f client_id -> clientId';
    is $c->[4][2]{clientSecret}, 's', 'create_github_enterprise_idp_f client_secret -> clientSecret';
    is $c->[4][2]{authorizationEndpoint}, 'https://a',
        'create_github_enterprise_idp_f authorization_endpoint -> authorizationEndpoint';
    is $c->[4][2]{tokenEndpoint}, 'https://t',
        'create_github_enterprise_idp_f token_endpoint -> tokenEndpoint';
    is $c->[4][2]{userEndpoint}, 'https://u',
        'create_github_enterprise_idp_f user_endpoint -> userEndpoint';

    # GitLab
    is $c->[5][1], '/idps/gitlab', 'create_gitlab_idp_f path';
    is $c->[5][2]{clientId}, 'c', 'create_gitlab_idp_f client_id -> clientId';

    # GitLab self-hosted
    is $c->[6][1], '/idps/gitlab_self_hosted', 'create_gitlab_self_hosted_idp_f path';
    is $c->[6][2]{issuer}, 'https://gl', 'create_gitlab_self_hosted_idp_f issuer';
    is $c->[6][2]{name}, 'GLS', 'create_gitlab_self_hosted_idp_f name';
    is $c->[6][2]{clientId}, 'c', 'create_gitlab_self_hosted_idp_f client_id -> clientId';
    is $c->[6][2]{clientSecret}, 's', 'create_gitlab_self_hosted_idp_f client_secret -> clientSecret';

    # Apple
    is $c->[7][1], '/idps/apple', 'create_apple_idp_f path';
    is $c->[7][2]{name}, 'AP', 'create_apple_idp_f name forwarded';
    is $c->[7][2]{clientId}, 'c', 'create_apple_idp_f client_id -> clientId';
    is $c->[7][2]{teamId}, 't', 'create_apple_idp_f team_id -> teamId';
    is $c->[7][2]{keyId}, 'k', 'create_apple_idp_f key_id -> keyId';
    is decode_base64($c->[7][2]{privateKey}), 'PK', 'create_apple_idp_f private_key base64-encoded';
    is_deeply $c->[7][2]{scopes}, ['email'], 'create_apple_idp_f scopes forwarded';

    # LDAP
    is $c->[8][1], '/idps/ldap', 'create_ldap_idp_f path';
    is $c->[8][2]{name}, 'L', 'create_ldap_idp_f name';
    is_deeply $c->[8][2]{servers}, ['ldap://x'], 'create_ldap_idp_f servers forwarded';
    ok $c->[8][2]{startTls}, 'create_ldap_idp_f start_tls -> startTls';
    is $c->[8][2]{baseDn}, 'dc=x', 'create_ldap_idp_f base_dn -> baseDn';
    is $c->[8][2]{bindDn}, 'cn=y', 'create_ldap_idp_f bind_dn -> bindDn';
    is $c->[8][2]{bindPassword}, 'p', 'create_ldap_idp_f bind_password -> bindPassword';
    is $c->[8][2]{userBase}, 'ou=users', 'create_ldap_idp_f user_base -> userBase';
    is_deeply $c->[8][2]{userObjectClasses}, ['person'],
        'create_ldap_idp_f user_object_classes -> userObjectClasses';
    is_deeply $c->[8][2]{userFilters}, ['cn'], 'create_ldap_idp_f user_filters -> userFilters';
    is $c->[8][2]{timeout}, 5, 'create_ldap_idp_f timeout forwarded';
    is decode_base64($c->[8][2]{rootCa}), 'PEM', 'create_ldap_idp_f root_ca base64-encoded';

    throws_ok { $m->create_jwt_idp_f(name => 'J') }
        qr/issuer required/, 'create_jwt_idp_f validates issuer';
    throws_ok { $m->create_google_idp_f() }
        qr/client_id required/, 'create_google_idp_f validates client_id (name optional)';
    throws_ok { $m->create_azuread_idp_f(client_id => 'c', client_secret => 's') }
        qr/name required/, 'create_azuread_idp_f validates name';
    throws_ok { $m->create_github_enterprise_idp_f(name => 'x', client_id => 'c', client_secret => 's') }
        qr/authorization_endpoint required/, 'create_github_enterprise_idp_f validates authorization_endpoint';
    throws_ok { $m->create_gitlab_self_hosted_idp_f(name => 'x', client_id => 'c', client_secret => 's') }
        qr/issuer required/, 'create_gitlab_self_hosted_idp_f validates issuer';
    throws_ok { $m->create_apple_idp_f(client_id => 'c', team_id => 't', key_id => 'k') }
        qr/private_key required/, 'create_apple_idp_f validates private_key';
    throws_ok { $m->create_ldap_idp_f(name => 'L') }
        qr/servers required/, 'create_ldap_idp_f validates servers';
    throws_ok { $m->create_ldap_idp_f(name => 'L', servers => ['x']) }
        qr/base_dn required/, 'create_ldap_idp_f validates base_dn after servers';
}

# --- Project roles and SAML / API applications ---

{
    my $m = _recorder();

    $m->update_project_role_f('p1', 'admin', display_name => 'Admin', group => 'g');
    $m->remove_project_role_f('p1', 'admin');
    $m->create_saml_app_f('p1', name => 'S', metadata_xml => '<?xml version="1.0"?><md/>');
    $m->create_saml_app_f('p1', name => 'S2', metadata_url => 'https://m');
    $m->update_saml_app_f('p1', 'a1', metadata_xml => '<?xml version="1.0"?><md/>');
    $m->create_api_app_f('p1', name => 'A', auth_method => 'API_AUTH_METHOD_TYPE_BASIC');

    my $c = $m->calls;

    is $c->[0][0], 'PUT', 'update_project_role_f uses PUT';
    is $c->[0][1], '/projects/p1/roles/admin', 'update_project_role_f path';
    is $c->[0][2]{displayName}, 'Admin', 'update_project_role_f display_name -> displayName';
    is $c->[0][2]{group}, 'g', 'update_project_role_f group forwarded';

    is_deeply $c->[1], ['DELETE', '/projects/p1/roles/admin', undef], 'remove_project_role_f path';

    is $c->[2][0], 'POST', 'create_saml_app_f (xml) uses POST';
    is $c->[2][1], '/projects/p1/apps/saml', 'create_saml_app_f (xml) path';
    is $c->[2][2]{name}, 'S', 'create_saml_app_f (xml) name';
    is decode_base64($c->[2][2]{metadataXml}), '<?xml version="1.0"?><md/>',
        'create_saml_app_f metadata_xml base64-encoded';

    is $c->[3][1], '/projects/p1/apps/saml', 'create_saml_app_f (url) path';
    is $c->[3][2]{name}, 'S2', 'create_saml_app_f (url) name';
    is $c->[3][2]{metadataUrl}, 'https://m', 'create_saml_app_f metadata_url -> metadataUrl';
    ok !exists $c->[3][2]{metadataXml}, 'create_saml_app_f (url) omits metadataXml';

    is $c->[4][0], 'PUT', 'update_saml_app_f uses PUT';
    is $c->[4][1], '/projects/p1/apps/a1/saml_config', 'update_saml_app_f path';
    is decode_base64($c->[4][2]{metadataXml}), '<?xml version="1.0"?><md/>',
        'update_saml_app_f metadata_xml base64-encoded';

    is $c->[5][0], 'POST', 'create_api_app_f uses POST';
    is $c->[5][1], '/projects/p1/apps/api', 'create_api_app_f path';
    is $c->[5][2]{name}, 'A', 'create_api_app_f name';
    is $c->[5][2]{authMethodType}, 'API_AUTH_METHOD_TYPE_BASIC',
        'create_api_app_f auth_method -> authMethodType';

    throws_ok { $m->update_project_role_f(undef, 'admin', display_name => 'X') }
        qr/project_id required/, 'update_project_role_f validates project_id';
    throws_ok { $m->update_project_role_f('p1', undef, display_name => 'X') }
        qr/role_key required/, 'update_project_role_f validates role_key';
    throws_ok { $m->update_project_role_f('p1', 'admin') }
        qr/display_name required/, 'update_project_role_f validates display_name';
    throws_ok { $m->remove_project_role_f('p1', undef) }
        qr/role_key required/, 'remove_project_role_f validates role_key';
    throws_ok { $m->create_saml_app_f('p1', name => 'S') }
        qr/metadata_xml or metadata_url required/, 'create_saml_app_f requires metadata';
    throws_ok { $m->update_saml_app_f('p1', 'a1') }
        qr/metadata_xml or metadata_url required/, 'update_saml_app_f requires metadata';
    throws_ok { $m->create_api_app_f('p1') }
        qr/name required/, 'create_api_app_f validates name';
}

# --- Organization domains, reactivate_org, and user lock/unlock/resend ---

{
    my $m = _recorder();

    $m->reactivate_org_f;
    $m->add_org_domain_f('example.com');
    $m->generate_org_domain_validation_f('example.com', type => 'HTTP');
    $m->validate_org_domain_f('example.com');
    $m->set_primary_org_domain_f('example.com');
    $m->list_org_domains_f(limit => 10);
    $m->remove_org_domain_f('example.com');

    $m->lock_user_f('u1');
    $m->unlock_user_f('u1');
    $m->resend_email_verification_f('u1');

    my $c = $m->calls;

    is_deeply $c->[0], ['POST', '/orgs/me/_reactivate', {}], 'reactivate_org_f path';

    is $c->[1][0], 'POST', 'add_org_domain_f uses POST';
    is $c->[1][1], '/orgs/me/domains', 'add_org_domain_f path';
    is $c->[1][2]{domain}, 'example.com', 'add_org_domain_f domain in body';

    is $c->[2][1], '/orgs/me/domains/example.com/validation/_generate',
        'generate_org_domain_validation_f path';
    is $c->[2][2]{type}, 'HTTP', 'generate_org_domain_validation_f type forwarded';

    is_deeply $c->[3], ['POST', '/orgs/me/domains/example.com/validation/_validate', {}],
        'validate_org_domain_f path';
    is_deeply $c->[4], ['POST', '/orgs/me/domains/example.com/_set_primary', {}],
        'set_primary_org_domain_f path';

    is $c->[5][1], '/orgs/me/domains/_search', 'list_org_domains_f path';
    is $c->[5][2]{query}{limit}, 10, 'list_org_domains_f limit mapped';

    is_deeply $c->[6], ['DELETE', '/orgs/me/domains/example.com', undef], 'remove_org_domain_f path';

    is_deeply $c->[7], ['POST', '/users/u1/_lock', {}], 'lock_user_f path';
    is_deeply $c->[8], ['POST', '/users/u1/_unlock', {}], 'unlock_user_f path';
    is_deeply $c->[9], ['POST', '/users/u1/email/_resend_verification', {}],
        'resend_email_verification_f path';

    throws_ok { $m->add_org_domain_f(undef) }
        qr/domain required/, 'add_org_domain_f validates domain';
    throws_ok { $m->generate_org_domain_validation_f('example.com') }
        qr/type required/, 'generate_org_domain_validation_f validates type';
    throws_ok { $m->validate_org_domain_f(undef) }
        qr/domain required/, 'validate_org_domain_f validates domain';
    throws_ok { $m->set_primary_org_domain_f(undef) }
        qr/domain required/, 'set_primary_org_domain_f validates domain';
    throws_ok { $m->remove_org_domain_f(undef) }
        qr/domain required/, 'remove_org_domain_f validates domain';
    throws_ok { $m->lock_user_f(undef) }
        qr/user_id required/, 'lock_user_f validates user_id';
    throws_ok { $m->unlock_user_f(undef) }
        qr/user_id required/, 'unlock_user_f validates user_id';
    throws_ok { $m->resend_email_verification_f(undef) }
        qr/user_id required/, 'resend_email_verification_f validates user_id';
}

done_testing;
