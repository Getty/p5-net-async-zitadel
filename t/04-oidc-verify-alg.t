use strict;
use warnings;

use Test::More;
use JSON::MaybeXS qw(encode_json);
use Future;
use Crypt::JWT qw(encode_jwt);
use Crypt::PK::RSA;
use Crypt::PK::ECC;

use Net::Async::Zitadel::OIDC;

# Signature algorithm allow-list of verify_token_f, exercised through the real
# Crypt::JWT: the tokens are signed with locally generated keys and nothing
# below _decode_jwt is mocked. Only the HTTP layer is replaced.

my $ISSUER   = 'https://zitadel.example.com';
my $JWKS_URI = "$ISSUER/oauth/v2/keys";

{
    package Local::Response;

    sub new {
        my ($class, %args) = @_;
        bless \%args, $class;
    }

    sub is_success      { 1 }
    sub status_line     { '200 OK' }
    sub decoded_content { $_[0]->{decoded_content} }
}

{
    # Serves the discovery document and the JWKS by URL, any number of times,
    # as already-resolved Futures.
    package Local::KeyServerHTTP;

    sub new {
        my ($class, %args) = @_;
        bless { %args, gets => [] }, $class;
    }

    sub gets { $_[0]->{gets} }

    sub GET {
        my ($self, $url) = @_;
        push @{ $self->{gets} }, "$url";
        my $doc = "$url" eq $self->{jwks_uri}
            ? $self->{jwks}
            : { jwks_uri => $self->{jwks_uri} };
        return Future->done(Local::Response->new(
            decoded_content => JSON::MaybeXS::encode_json($doc),
        ));
    }
}

my $rsa = Crypt::PK::RSA->new;
$rsa->generate_key(256, 65537);
my $rsa_jwk = $rsa->export_key_jwk('public', 1);
$rsa_jwk->{kid} = 'rsa-1';

my $ecc = Crypt::PK::ECC->new;
$ecc->generate_key('secp256r1');
my $ecc_jwk = $ecc->export_key_jwk('public', 1);
$ecc_jwk->{kid} = 'ec-1';

my $JWKS = { keys => [ $rsa_jwk, $ecc_jwk ] };

sub _token {
    my ($alg) = @_;
    my ($key, $kid) = $alg =~ /^ES/ ? ($ecc, 'ec-1') : ($rsa, 'rsa-1');
    return encode_jwt(
        payload       => { iss => $ISSUER, sub => "user-$alg", exp => time + 300 },
        alg           => $alg,
        key           => $key,
        extra_headers => { kid => $kid },
    );
}

sub _oidc {
    my $http = Local::KeyServerHTTP->new(jwks_uri => $JWKS_URI, jwks => $JWKS);
    return Net::Async::Zitadel::OIDC->new(issuer => $ISSUER, http => $http);
}

sub _jwks_fetches {
    my ($oidc) = @_;
    return scalar grep { $_ eq $JWKS_URI } @{ $oidc->http->gets };
}

sub _accepted {
    my ($f, $alg, $name) = @_;
    ok !$f->is_failed, $name
        or diag $f->failure;
    my $claims = $f->is_done ? $f->get : {};
    is $claims->{sub}, "user-$alg", "$alg token yields its claims";
}

sub _rejected {
    my ($f, $re, $name) = @_;
    ok $f->is_failed, $name;
    like +($f->failure // ''), $re, "$name: Crypt::JWT names the algorithm";
}

# Default allow-list: RS256/RS384/RS512.
for my $alg (qw(RS256 RS384 RS512)) {
    _accepted(_oidc()->verify_token_f(_token($alg)), $alg,
        "$alg token is accepted by default");
}

# A validly signed token with an algorithm outside the default list is
# rejected, although its key is in the JWKS.
for my $alg (qw(PS256 ES256)) {
    _rejected(
        _oidc()->verify_token_f(_token($alg), no_retry => 1),
        qr/alg '\Q$alg\E' not in accepted_alg/,
        "$alg token is rejected by default",
    );
}

# The allow-list also holds on the second pass after the JWKS refresh.
{
    my $oidc = _oidc();
    _rejected(
        $oidc->verify_token_f(_token('PS256')),
        qr/alg 'PS256' not in accepted_alg/,
        'PS256 token is rejected by default after the JWKS refresh retry',
    );
    is _jwks_fetches($oidc), 2, 'the retry pass ran';
}

# Callers widen the list with accepted_alg ...
for my $alg (qw(PS256 ES256)) {
    _accepted(
        _oidc()->verify_token_f(_token($alg), accepted_alg => [$alg]), $alg,
        "$alg token is accepted when listed in accepted_alg",
    );
}

# ... and with the older option name accepted_key_alg.
_accepted(
    _oidc()->verify_token_f(_token('PS256'), accepted_key_alg => ['PS256']),
    'PS256',
    'PS256 token is accepted when listed in accepted_key_alg',
);

# A caller-supplied list narrows as well, under both names.
for my $opt (qw(accepted_alg accepted_key_alg)) {
    _rejected(
        _oidc()->verify_token_f(
            _token('RS256'), $opt => ['RS512'], no_retry => 1,
        ),
        qr/alg 'RS256' not in accepted_alg/,
        "RS256 token is rejected when $opt lists only RS512",
    );
}

# Scalar and Regexp forms are passed through to Crypt::JWT.
_accepted(
    _oidc()->verify_token_f(_token('ES256'), accepted_alg => 'ES256'),
    'ES256',
    'accepted_alg takes a single algorithm name',
);
_rejected(
    _oidc()->verify_token_f(
        _token('RS256'), accepted_alg => qr/^ES/, no_retry => 1,
    ),
    qr/alg 'RS256' does not match accepted_alg/,
    'accepted_alg takes a Regexp',
);

# accepted_alg wins when both names are given.
_rejected(
    _oidc()->verify_token_f(
        _token('PS256'),
        accepted_alg     => ['RS256'],
        accepted_key_alg => ['PS256'],
        no_retry         => 1,
    ),
    qr/alg 'PS256' not in accepted_alg/,
    'accepted_alg takes precedence over accepted_key_alg',
);

done_testing;
