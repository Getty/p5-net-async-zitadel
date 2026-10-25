use strict;
use warnings;
use Test::More;
use Test::Exception;

use Net::Async::Zitadel;
use Net::Async::Zitadel::OIDC;
use Net::Async::Zitadel::Management;
use Net::Async::Zitadel::Error;

# Facade constructor. Net::Async::Zitadel is a Moo class that extends the
# non-Moo IO::Async::Notifier; regression for karr #2, where the documented
# new(issuer => ..., token => ...) died with "Unrecognised configuration keys".
# Offline: http/oidc/management are lazy, so construction makes no network call.
{
    my $z;
    lives_ok {
        $z = Net::Async::Zitadel->new(
            issuer => 'https://zitadel.example.com',
            token  => 'pat',
        );
    } 'facade new(issuer, token) does not die';
    ok $z && $z->isa('IO::Async::Notifier'), 'facade isa IO::Async::Notifier';
    is $z->issuer, 'https://zitadel.example.com', 'facade issuer set';
    is $z->token,  'pat', 'facade token set';
    isa_ok $z->oidc,       'Net::Async::Zitadel::OIDC';
    isa_ok $z->management, 'Net::Async::Zitadel::Management';

    # empty issuer still rejected by BUILD
    throws_ok { Net::Async::Zitadel->new(issuer => '') }
        qr/issuer must not be empty/, 'facade rejects empty issuer';

    # token is optional; management then dies asking for a token
    my $z2 = Net::Async::Zitadel->new(issuer => 'https://zitadel.example.com');
    throws_ok { $z2->management }
        qr/requires a token/, 'facade management dies without token';
}

# The default HTTP client must not wait for ever on a silent server, and must
# not follow a redirect (it would resend the Authorization header). Net::Async::HTTP
# has no accessors for these, so the settings are read from the object itself.
{
    my $http = Net::Async::Zitadel->new(issuer => 'https://zitadel.example.com')->http;
    isa_ok $http, 'Net::Async::HTTP';
    is $http->{timeout},       30, 'default http client has a 30s timeout';
    is $http->{max_redirects},  0, 'default http client follows no redirects';
    ok defined $http->{fail_on_error} && !$http->{fail_on_error},
        'default http client hands back non-2xx responses (fail_on_error off)';

    my $mine = bless {}, 'Local::FakeHTTP';
    is(Net::Async::Zitadel->new(
        issuer => 'https://zitadel.example.com', http => $mine,
    )->http, $mine, 'an injected http client is used untouched');
}

# OIDC requires issuer
throws_ok { Net::Async::Zitadel::OIDC->new(http => bless {}, 'Local::FakeHTTP') }
    qr/required/, 'OIDC needs issuer';
throws_ok {
    Net::Async::Zitadel::OIDC->new(issuer => '', http => bless {}, 'Local::FakeHTTP')
} qr/issuer must not be empty/, 'OIDC rejects empty issuer';
{
    eval { Net::Async::Zitadel::OIDC->new(issuer => '', http => bless {}, 'Local::FakeHTTP') };
    ok ref $@ && $@->isa('Net::Async::Zitadel::Error::Validation'),
        'empty issuer throws Validation exception';
}

# Management requires base_url and token
throws_ok { Net::Async::Zitadel::Management->new(http => bless {}, 'Local::FakeHTTP') }
    qr/required/, 'Management needs base_url + token';
throws_ok {
    Net::Async::Zitadel::Management->new(
        base_url => '',
        token    => 'x',
        http     => bless {}, 'Local::FakeHTTP',
    )
} qr/base_url must not be empty/, 'Management rejects empty base_url';
{
    eval {
        Net::Async::Zitadel::Management->new(
            base_url => '',
            token    => 'x',
            http     => bless {}, 'Local::FakeHTTP',
        );
    };
    ok ref $@ && $@->isa('Net::Async::Zitadel::Error::Validation'),
        'empty base_url throws Validation exception';
}

# Error class hierarchy and stringification
{
    my $api = Net::Async::Zitadel::Error::API->new(
        message     => 'API error: 404 Not Found - user not found',
        http_status => '404 Not Found',
        api_message => 'user not found',
    );
    is "$api", 'API error: 404 Not Found - user not found', 'API error stringifies';
    is $api->http_status, '404 Not Found', 'API error http_status';
    is $api->api_message, 'user not found', 'API error api_message';
    ok $api->isa('Net::Async::Zitadel::Error'), 'API error isa base Error';

    my $net = Net::Async::Zitadel::Error::Network->new(
        message => 'Discovery failed: 503 Service Unavailable',
    );
    is "$net", 'Discovery failed: 503 Service Unavailable', 'Network error stringifies';
    ok $net->isa('Net::Async::Zitadel::Error'), 'Network error isa base Error';

    my $val = Net::Async::Zitadel::Error::Validation->new(message => 'user_id required');
    is "$val", 'user_id required', 'Validation error stringifies';
}

# verify_token_f validation fails immediately without HTTP
{
    my $oidc = Net::Async::Zitadel::OIDC->new(
        issuer => 'https://zitadel.example.com',
        http   => bless {}, 'Local::FakeHTTP',
    );

    my $f = $oidc->verify_token_f(undef);
    ok $f->is_failed, 'verify_token_f(undef) returns failed Future';
    eval { $f->get };
    like "$@", qr/No token provided/, 'failed Future propagates Validation message';
}

# Management validation errors are immediate
{
    my $mgmt = Net::Async::Zitadel::Management->new(
        base_url => 'https://zitadel.example.com',
        token    => 'pat',
        http     => bless {}, 'Local::FakeHTTP',
    );

    throws_ok { $mgmt->get_user_f(undef) }    qr/user_id required/,    'get_user_f validates user_id';
    throws_ok { $mgmt->get_project_f(undef) } qr/project_id required/, 'get_project_f validates project_id';
    throws_ok { $mgmt->get_app_f(undef, 'a') } qr/project_id required/, 'get_app_f validates project_id';
    throws_ok { $mgmt->get_app_f('p', undef) } qr/app_id required/,    'get_app_f validates app_id';
}

done_testing;
