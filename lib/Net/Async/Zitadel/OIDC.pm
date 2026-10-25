package Net::Async::Zitadel::OIDC;

# ABSTRACT: Async OIDC client for Zitadel - token verification, JWKS, discovery

use Moo;
use Crypt::JWT qw(decode_jwt);
use JSON::MaybeXS qw(decode_json);
use HTTP::Request;
use URI;
use Future;
use Scalar::Util qw(refaddr weaken);
use Net::Async::Zitadel::Error;
use namespace::clean;

our $VERSION = '0.002';

has issuer => (
    is       => 'ro',
    required => 1,
);

sub BUILD {
    my $self = shift;
    die Net::Async::Zitadel::Error::Validation->new(
        message => 'issuer must not be empty',
    ) unless length $self->issuer;
}

has http => (
    is       => 'ro',
    required => 1,
    doc      => 'Net::Async::HTTP instance (shared from parent)',
);

=attr discovery_ttl

How many seconds to cache the OpenID Connect discovery document before
re-fetching. Default: C<3600> (one hour). Set to C<0> to disable caching.

=attr jwks_ttl

How many seconds to cache the JSON Web Key Set before re-fetching. Default:
C<300> (five minutes). Set to C<0> to disable caching.

=cut

has discovery_ttl => (
    is      => 'ro',
    default => 3600,
);

has jwks_ttl => (
    is      => 'ro',
    default => 300,
);

=attr jwks_min_age

Seconds that have to pass before L</verify_token_f> fetches the keys again for
a token that names an unknown key. Default: C<60>, so that a stream of forged
tokens does not become a stream of requests to Zitadel. Same attribute and
default as L<WWW::Zitadel::OIDC>.

=cut

has jwks_min_age => (
    is      => 'ro',
    default => 60,
);

# When the keys were last fetched by a forced refresh. The first, cached
# fetch does not count: the first token with an unknown key has to be able to
# trigger a refresh right away.
has _jwks_fetched => (
    is       => 'rw',
    init_arg => undef,
    default  => sub { 0 },
);

has _discovery_cache => (
    is      => 'rw',
    default => sub { undef },
);

has _discovery_expires => (
    is      => 'rw',
    default => sub { 0 },
);

has _jwks_cache => (
    is      => 'rw',
    default => sub { undef },
);

has _jwks_expires => (
    is      => 'rw',
    default => sub { 0 },
);

# Stores the in-flight JWKS Future to coalesce concurrent refresh requests.
has _jwks_inflight => (
    is      => 'rw',
    default => sub { undef },
);

# --- Discovery ---

sub discovery_f {
    my ($self) = @_;

    if ($self->_discovery_cache && time() < $self->_discovery_expires) {
        return Future->done($self->_discovery_cache);
    }

    my $url = $self->issuer . '/.well-known/openid-configuration';

    return $self->http->GET(URI->new($url))->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail(Net::Async::Zitadel::Error::Network->new(
                message => 'Discovery failed: ' . $response->status_line,
            ));
        }
        my $doc = decode_json($response->decoded_content);
        $self->_discovery_cache($doc);
        $self->_discovery_expires(time() + $self->discovery_ttl);
        return Future->done($doc);
    });
}

# --- JWKS ---

sub jwks_f {
    my ($self, %args) = @_;
    my $force = $args{force_refresh} // 0;

    if (!$force && $self->_jwks_cache && time() < $self->_jwks_expires) {
        return Future->done($self->_jwks_cache);
    }

    # Coalesce concurrent JWKS refreshes, forced ones included: if a fetch is
    # already in-flight, hand out a Future derived from it rather than issuing
    # a second HTTP request. without_cancel keeps one caller's cancel() from
    # tearing down the fetch the others are waiting for.
    if (my $inflight = $self->_jwks_inflight) {
        return $inflight->without_cancel;
    }

    # A forced refresh is the one verify_token_f rate-limits; note when it
    # started, so a failed fetch holds off the next one as well.
    $self->_jwks_fetched(time()) if $force;

    my $f = $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $jwks_uri = $doc->{jwks_uri}
            // return Future->fail(Net::Async::Zitadel::Error::Validation->new(
                message => 'No jwks_uri in discovery document',
            ));
        return $self->http->GET(URI->new($jwks_uri));
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail(Net::Async::Zitadel::Error::Network->new(
                message => 'JWKS fetch failed: ' . $response->status_line,
            ));
        }
        my $jwks = decode_json($response->decoded_content);
        $self->_jwks_cache($jwks);
        $self->_jwks_expires(time() + $self->jwks_ttl);
        return Future->done($jwks);
    });

    # Store the fetch only while it is pending: a chain that resolved
    # synchronously has nothing to coalesce onto. on_ready frees the slot on
    # success, failure and cancellation alike; it compares the Future it is
    # handed, so it neither captures $f nor wipes a newer fetch's slot.
    unless ($f->is_ready) {
        $self->_jwks_inflight($f);
        weaken(my $weak_self = $self);
        $f->on_ready(sub {
            my ($done) = @_;
            my $slot = $weak_self && $weak_self->_jwks_inflight;
            $weak_self->_jwks_inflight(undef)
                if $slot && refaddr($slot) == refaddr($done);
        });
    }
    return $f->without_cancel;
}

# --- Token verification ---

sub verify_token_f {
    my ($self, $token, %args) = @_;

    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'No token provided',
    )) unless defined $token;

    # Crypt::JWT pins the signature algorithm through accepted_alg and
    # silently ignores option names it does not know, so the list has to be
    # handed over under exactly that name. accepted_key_alg is the name this
    # method took first and stays as an alias.
    my $accepted_alg = $args{accepted_alg}
        // $args{accepted_key_alg}
        // ['RS256', 'RS384', 'RS512'];

    my %check = (
        token        => $token,
        verify_exp   => $args{verify_exp} // 1,
        verify_iat   => $args{verify_iat} // 0,
        verify_nbf   => $args{verify_nbf} // 0,
        verify_iss   => $self->issuer,
        verify_aud   => $args{audience},
        accepted_alg => $accepted_alg,
    );

    return $self->jwks_f->then(sub {
        my ($jwks) = @_;

        my $claims = eval { $self->_decode_jwt(%check, kid_keys => $jwks) };
        my $error  = $@;
        return Future->done($claims) unless $error;

        # Key rotation: only an unknown key can be cured by new keys. Every
        # other rejection (expired, wrong issuer or audience, bad signature)
        # is the token's own fault, fails with its original error and costs
        # no request to the issuer. The refresh happens at most once per
        # jwks_min_age, so a stream of forged tokens does not become a
        # stream of requests either.
        return Future->fail($error)
            if $args{no_retry}
            || $error !~ /kid_keys lookup failed/
            || time() - $self->_jwks_fetched < $self->jwks_min_age;

        return $self->jwks_f(force_refresh => 1)->then(sub {
            my ($fresh_jwks) = @_;
            return Future->done(
                $self->_decode_jwt(%check, kid_keys => $fresh_jwks));
        });
    });
}

sub _decode_jwt {
    my ($self, %args) = @_;
    return decode_jwt(%args);
}

# --- UserInfo ---

sub userinfo_f {
    my ($self, $access_token) = @_;

    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'No access token provided',
    )) unless defined $access_token;

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{userinfo_endpoint}
            // return Future->fail(Net::Async::Zitadel::Error::Validation->new(
                message => 'No userinfo_endpoint in discovery document',
            ));
        my $req = HTTP::Request->new(GET => $endpoint);
        $req->header(Authorization => "Bearer $access_token");
        return $self->http->do_request(request => $req);
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail(Net::Async::Zitadel::Error::Network->new(
                message => 'UserInfo failed: ' . $response->status_line,
            ));
        }
        return Future->done(decode_json($response->decoded_content));
    });
}

# --- Token Introspection ---

sub introspect_f {
    my ($self, $token, %args) = @_;

    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'No token provided',
    )) unless defined $token;

    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'Introspection requires client_id and client_secret',
    )) unless $args{client_id} && $args{client_secret};

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{introspection_endpoint}
            // return Future->fail(Net::Async::Zitadel::Error::Validation->new(
                message => 'No introspection_endpoint in discovery document',
            ));

        my $form = URI->new;
        $form->query_form(
            token           => $token,
            client_id       => $args{client_id},
            client_secret   => $args{client_secret},
            token_type_hint => $args{token_type_hint} // 'access_token',
        );

        my $req = HTTP::Request->new(POST => $endpoint);
        $req->header('Content-Type' => 'application/x-www-form-urlencoded');
        $req->content($form->query);

        return $self->http->do_request(request => $req);
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail(Net::Async::Zitadel::Error::Network->new(
                message => 'Introspection failed: ' . $response->status_line,
            ));
        }
        return Future->done(decode_json($response->decoded_content));
    });
}

# --- Token Endpoint ---

sub token_f {
    my ($self, %args) = @_;

    my $grant_type = delete $args{grant_type};
    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'grant_type required',
    )) unless defined $grant_type;

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{token_endpoint}
            // return Future->fail(Net::Async::Zitadel::Error::Validation->new(
                message => 'No token_endpoint in discovery document',
            ));

        my $form = URI->new;
        $form->query_form(grant_type => $grant_type, %args);

        my $req = HTTP::Request->new(POST => $endpoint);
        $req->header('Content-Type' => 'application/x-www-form-urlencoded');
        $req->content($form->query);

        return $self->http->do_request(request => $req);
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail(Net::Async::Zitadel::Error::Network->new(
                message => 'Token endpoint failed: ' . $response->status_line,
            ));
        }
        return Future->done(decode_json($response->decoded_content));
    });
}

sub client_credentials_token_f {
    my ($self, %args) = @_;

    my $client_id = delete $args{client_id};
    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'client_id required',
    )) unless defined $client_id;

    my $client_secret = delete $args{client_secret};
    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'client_secret required',
    )) unless defined $client_secret;

    return $self->token_f(
        grant_type    => 'client_credentials',
        client_id     => $client_id,
        client_secret => $client_secret,
        %args,
    );
}

sub refresh_token_f {
    my ($self, $refresh_token, %args) = @_;

    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'refresh_token required',
    )) unless defined $refresh_token && length $refresh_token;

    return $self->token_f(
        grant_type    => 'refresh_token',
        refresh_token => $refresh_token,
        %args,
    );
}

sub exchange_authorization_code_f {
    my ($self, %args) = @_;

    my $code = delete $args{code};
    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'code required',
    )) unless defined $code;

    my $redirect_uri = delete $args{redirect_uri};
    return Future->fail(Net::Async::Zitadel::Error::Validation->new(
        message => 'redirect_uri required',
    )) unless defined $redirect_uri;

    return $self->token_f(
        grant_type   => 'authorization_code',
        code         => $code,
        redirect_uri => $redirect_uri,
        %args,
    );
}

1;

__END__

=head1 SYNOPSIS

    use IO::Async::Loop;
    use Net::Async::Zitadel;

    my $loop = IO::Async::Loop->new;
    my $z = Net::Async::Zitadel->new(issuer => 'https://zitadel.example.com');
    $loop->add($z);

    # Async token verification
    my $claims = $z->oidc->verify_token_f($access_token)->get;

    # Async userinfo
    my $user = $z->oidc->userinfo_f($access_token)->get;

    # Async client credentials token
    my $token = $z->oidc->client_credentials_token_f(
        client_id     => $id,
        client_secret => $secret,
    )->get;

=head1 DESCRIPTION

Async OIDC client for Zitadel, built on L<Net::Async::HTTP> and L<Future>.
All methods return L<Future> objects (C<_f> suffix convention).

Token verification retries with a refreshed JWKS when a token names a key
the cached set does not have, handling key rotation transparently. Concurrent
JWKS requests, forced refreshes included, are coalesced: if a fetch is
already in-flight, subsequent callers receive a Future derived from it
rather than triggering a second HTTP request. Cancelling one caller's Future
does not cancel the shared fetch.

=attr issuer

Required. The Zitadel issuer URL. Must not be empty.

=attr http

Required. A L<Net::Async::HTTP> instance (typically shared from
L<Net::Async::Zitadel>).

=method discovery_f

Returns a Future resolving to the parsed OpenID Connect discovery document.
Cached after first fetch.

=method jwks_f

Returns a Future resolving to the JSON Web Key Set. Cached after first fetch.
Pass C<< force_refresh => 1 >> to bypass the cache. Concurrent calls, forced
or not, coalesce into the same in-flight request; each caller gets its own
Future, so cancelling one leaves the request and the other callers alone.

=method verify_token_f

    my $f = $oidc->verify_token_f($jwt, %options);

Returns a Future resolving to the decoded claims hashref. Options:
C<audience>, C<verify_exp>, C<verify_iat>, C<verify_nbf>,
C<accepted_alg> (default RS256/384/512), C<no_retry>.

A token that names a key the JWKS does not have makes the keys be fetched
again and the token be decoded once more; that happens at most once per
L</jwks_min_age>. Every other rejection - an expired token, the wrong
issuer, a bad signature - fails the Future with the original error and does
not fetch the keys again. C<no_retry> turns the refresh off.

C<accepted_alg> is the allow-list of signature algorithms and is passed to
L<Crypt::JWT> as its C<accepted_alg>: an algorithm name, an arrayref of names
or a C<Regexp>. A token signed with any other algorithm is rejected, even if
its key is in the JWKS. The default accepts RSA PKCS#1 v1.5 signatures only;
an instance that signs with ECDSA or Ed25519 keys needs the list widened:

    my $f = $oidc->verify_token_f($jwt,
        accepted_alg => ['RS256', 'ES256', 'EdDSA'],
    );

C<accepted_key_alg> is the older name of the same option and is still
accepted; C<accepted_alg> wins if both are given.

=method userinfo_f

    my $f = $oidc->userinfo_f($access_token);

Returns a Future resolving to the UserInfo endpoint response.

=method introspect_f

    my $f = $oidc->introspect_f($token,
        client_id     => $id,
        client_secret => $secret,
    );

Returns a Future resolving to the token introspection response.

=method token_f

    my $f = $oidc->token_f(grant_type => 'client_credentials', %params);

Generic async token endpoint POST (form-encoded). Returns a Future.

=method client_credentials_token_f

Convenience wrapper for C<client_credentials> grant.

=method refresh_token_f

Convenience wrapper for C<refresh_token> grant.

=method exchange_authorization_code_f

Convenience wrapper for C<authorization_code> grant.

=head1 SEE ALSO

L<Net::Async::Zitadel>, L<WWW::Zitadel::OIDC>, L<Crypt::JWT>, L<Future>

=cut
