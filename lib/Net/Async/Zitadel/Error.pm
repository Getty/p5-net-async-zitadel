package Net::Async::Zitadel::Error;

# ABSTRACT: Structured exception base class for Net::Async::Zitadel

use Moo;

# namespace::clean must NOT be used here: it would strip the overload
# operator stub installed by 'use overload' below.
use overload '""' => sub { $_[0]->message }, fallback => 1;

our $VERSION = '0.002';

=attr message

Human-readable error description. The object stringifies to this value,
so C<eval>/C<$@>/C<Future> failure string-matching patterns continue to work.

=cut

has message => (
    is       => 'ro',
    required => 1,
);

# Concrete subclasses live one-per-file (Error/Validation.pm, Error/Network.pm,
# Error/API.pm). Load them here so `use Net::Async::Zitadel::Error` still pulls
# in the whole family — callers only ever `use` this module, then reference
# ::Validation / ::Network / ::API. Required at runtime, after the base class is
# defined, so each subclass's `extends 'Net::Async::Zitadel::Error'` resolves.
require Net::Async::Zitadel::Error::Validation;
require Net::Async::Zitadel::Error::Network;
require Net::Async::Zitadel::Error::API;

1;

__END__

=head1 SYNOPSIS

    use Net::Async::Zitadel::Error;

    $z->oidc->verify_token_f($jwt)->then(sub {
        my ($claims) = @_;
        ...
    })->catch(sub {
        my ($err) = @_;
        if (ref $err && $err->isa('Net::Async::Zitadel::Error::API')) {
            warn "API error (HTTP " . $err->http_status . "): $err";
        }
        elsif (ref $err && $err->isa('Net::Async::Zitadel::Error::Validation')) {
            warn "Bad argument: $err";
        }
        else {
            Future->fail($err);
        }
    });

=head1 DESCRIPTION

C<Net::Async::Zitadel::Error> is the exception base class. Loading it also loads
its three concrete subclasses, each of which C<extends> this class and inherits
the stringification overload:

=over 4

=item L<Net::Async::Zitadel::Error::Validation>

Missing/invalid arguments, empty issuer/base_url.

=item L<Net::Async::Zitadel::Error::Network>

OIDC endpoint HTTP failures (discovery, JWKS, userinfo, token).

=item L<Net::Async::Zitadel::Error::API>

Management API non-2xx responses. Carries C<http_status> and C<api_message>.

=back

All classes stringify to C<message> for backward compatibility.

=head1 SEE ALSO

L<Net::Async::Zitadel>, L<Net::Async::Zitadel::OIDC>, L<Net::Async::Zitadel::Management>

=cut
