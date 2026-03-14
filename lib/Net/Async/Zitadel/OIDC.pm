package Net::Async::Zitadel::OIDC;

# ABSTRACT: Async OIDC client for Zitadel - token verification, JWKS, discovery

use Moo;
use Crypt::JWT qw(decode_jwt);
use JSON::MaybeXS qw(decode_json);
use URI;
use Future;
use namespace::clean;

our $VERSION = '0.001';

has issuer => (
    is       => 'ro',
    required => 1,
);

has http => (
    is       => 'ro',
    required => 1,
    doc      => 'Net::Async::HTTP instance (shared from parent)',
);

has _discovery_cache => (
    is      => 'rw',
    default => sub { undef },
);

has _jwks_cache => (
    is      => 'rw',
    default => sub { undef },
);

# --- Discovery ---

sub discovery_f {
    my ($self) = @_;

    if ($self->_discovery_cache) {
        return Future->done($self->_discovery_cache);
    }

    my $url = $self->issuer . '/.well-known/openid-configuration';

    return $self->http->GET(URI->new($url))->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail("Discovery failed: " . $response->status_line . "\n");
        }
        my $doc = decode_json($response->decoded_content);
        $self->_discovery_cache($doc);
        return Future->done($doc);
    });
}

# --- JWKS ---

sub jwks_f {
    my ($self, %args) = @_;
    my $force = $args{force_refresh} // 0;

    if (!$force && $self->_jwks_cache) {
        return Future->done($self->_jwks_cache);
    }

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $jwks_uri = $doc->{jwks_uri}
            // return Future->fail("No jwks_uri in discovery document\n");
        return $self->http->GET(URI->new($jwks_uri));
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail("JWKS fetch failed: " . $response->status_line . "\n");
        }
        my $jwks = decode_json($response->decoded_content);
        $self->_jwks_cache($jwks);
        return Future->done($jwks);
    });
}

# --- Token verification ---

sub verify_token_f {
    my ($self, $token, %args) = @_;
    die "No token provided\n" unless defined $token;

    return $self->jwks_f->then(sub {
        my ($jwks) = @_;

        my $claims;
        eval {
            $claims = decode_jwt(
                token            => $token,
                kid_keys         => $jwks,
                verify_exp       => $args{verify_exp} // 1,
                verify_iat       => $args{verify_iat} // 0,
                verify_nbf       => $args{verify_nbf} // 0,
                verify_iss       => $self->issuer,
                verify_aud       => $args{audience},
                accepted_key_alg => $args{accepted_key_alg} // ['RS256', 'RS384', 'RS512'],
            );
        };
        if ($@ && !$args{no_retry}) {
            # Key rotation: refresh JWKS and retry once
            return $self->jwks_f(force_refresh => 1)->then(sub {
                my ($fresh_jwks) = @_;
                my $retry_claims = decode_jwt(
                    token            => $token,
                    kid_keys         => $fresh_jwks,
                    verify_exp       => $args{verify_exp} // 1,
                    verify_iat       => $args{verify_iat} // 0,
                    verify_nbf       => $args{verify_nbf} // 0,
                    verify_iss       => $self->issuer,
                    verify_aud       => $args{audience},
                    accepted_key_alg => $args{accepted_key_alg} // ['RS256', 'RS384', 'RS512'],
                );
                return Future->done($retry_claims);
            });
        }
        elsif ($@) {
            return Future->fail($@);
        }

        return Future->done($claims);
    });
}

# --- UserInfo ---

sub userinfo_f {
    my ($self, $access_token) = @_;
    die "No access token provided\n" unless defined $access_token;

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{userinfo_endpoint}
            // return Future->fail("No userinfo_endpoint in discovery document\n");
        return $self->http->GET(
            URI->new($endpoint),
            headers => { Authorization => "Bearer $access_token" },
        );
    })->then(sub {
        my ($response) = @_;
        unless ($response->is_success) {
            return Future->fail("UserInfo failed: " . $response->status_line . "\n");
        }
        return Future->done(decode_json($response->decoded_content));
    });
}

# --- Token Introspection ---

sub introspect_f {
    my ($self, $token, %args) = @_;
    die "No token provided\n" unless defined $token;
    die "Introspection requires client_id and client_secret\n"
        unless $args{client_id} && $args{client_secret};

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{introspection_endpoint}
            // return Future->fail("No introspection_endpoint in discovery document\n");

        # TODO: POST form-encoded request to introspection endpoint
        # Fields: token, client_id, client_secret, token_type_hint
        # Use $self->http->POST or ->do_request with form content
        return Future->fail("introspect_f not yet implemented\n");
    });
}

# --- Token Endpoint ---

sub token_f {
    my ($self, %args) = @_;

    my $grant_type = delete $args{grant_type}
        // die "grant_type required\n";

    return $self->discovery_f->then(sub {
        my ($doc) = @_;
        my $endpoint = $doc->{token_endpoint}
            // return Future->fail("No token_endpoint in discovery document\n");

        # TODO: POST form-encoded request to token endpoint
        # Fields: grant_type + remaining %args
        # Use $self->http->POST or ->do_request with form content
        return Future->fail("token_f not yet implemented\n");
    });
}

sub client_credentials_token_f {
    my ($self, %args) = @_;

    my $client_id = delete $args{client_id}
        // die "client_id required\n";
    my $client_secret = delete $args{client_secret}
        // die "client_secret required\n";

    return $self->token_f(
        grant_type    => 'client_credentials',
        client_id     => $client_id,
        client_secret => $client_secret,
        %args,
    );
}

sub refresh_token_f {
    my ($self, $refresh_token, %args) = @_;
    die "refresh_token required\n" unless defined $refresh_token && length $refresh_token;

    return $self->token_f(
        grant_type    => 'refresh_token',
        refresh_token => $refresh_token,
        %args,
    );
}

sub exchange_authorization_code_f {
    my ($self, %args) = @_;

    my $code = delete $args{code}
        // die "code required\n";
    my $redirect_uri = delete $args{redirect_uri}
        // die "redirect_uri required\n";

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

    # Async discovery
    my $config = $z->oidc->discovery_f->get;

    # Async JWKS
    my $jwks = $z->oidc->jwks_f->get;

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

Token verification automatically retries with a refreshed JWKS on failure,
handling key rotation transparently.

=attr issuer

Required. The Zitadel issuer URL.

=attr http

Required. A L<Net::Async::HTTP> instance (typically shared from L<Net::Async::Zitadel>).

=method discovery_f

Returns a Future that resolves to the parsed OpenID Connect discovery document.
Cached after first fetch.

=method jwks_f

Returns a Future that resolves to the JSON Web Key Set.
Cached after first fetch. Pass C<< force_refresh => 1 >> to bypass cache.

=method verify_token_f

    my $f = $oidc->verify_token_f($jwt, %options);

Returns a Future that resolves to the decoded claims hashref, or fails on
verification error. Automatically retries with fresh JWKS on key mismatch.

Options: C<audience>, C<verify_exp>, C<verify_iat>, C<verify_nbf>,
C<accepted_key_alg>, C<no_retry>.

=method userinfo_f

    my $f = $oidc->userinfo_f($access_token);

Returns a Future that resolves to the UserInfo response.

=method introspect_f

    my $f = $oidc->introspect_f($token, client_id => ..., client_secret => ...);

Returns a Future that resolves to the introspection response.
B<TODO: not yet implemented.>

=method token_f

    my $f = $oidc->token_f(grant_type => '...', %params);

Generic async token endpoint call. Returns a Future.
B<TODO: not yet implemented.>

=method client_credentials_token_f

Convenience wrapper for C<client_credentials> grant type.

=method refresh_token_f

Convenience wrapper for C<refresh_token> grant type.

=method exchange_authorization_code_f

Convenience wrapper for C<authorization_code> grant type.

=head1 SEE ALSO

L<Net::Async::Zitadel>, L<WWW::Zitadel::OIDC>, L<Crypt::JWT>, L<Future>

=cut
