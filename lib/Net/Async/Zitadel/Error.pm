package Net::Async::Zitadel::Error;

# ABSTRACT: Structured exception classes for Net::Async::Zitadel

use Moo;

# namespace::clean must NOT be used here: it would strip the overload
# operator stub installed by 'use overload' below.
use overload '""' => sub { $_[0]->message }, fallback => 1;

our $VERSION = '0.001';

=attr message

Human-readable error description. The object stringifies to this value,
so C<eval>/C<$@>/C<Future> failure string-matching patterns continue to work.

=cut

has message => (
    is       => 'ro',
    required => 1,
);

package Net::Async::Zitadel::Error::Validation;

use Moo;
extends 'Net::Async::Zitadel::Error';
use namespace::clean;

package Net::Async::Zitadel::Error::Network;

use Moo;
extends 'Net::Async::Zitadel::Error';
use namespace::clean;

package Net::Async::Zitadel::Error::API;

use Moo;
extends 'Net::Async::Zitadel::Error';
use namespace::clean;

=attr http_status

The HTTP status line returned by the server, e.g. C<"400 Bad Request">.

=attr api_message

The C<message> field from the JSON error body, if present.

=cut

has http_status => ( is => 'ro' );
has api_message => ( is => 'ro' );

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

Three exception classes, all inheriting from C<Net::Async::Zitadel::Error>:

=over 4

=item C<Net::Async::Zitadel::Error::Validation>

Missing/invalid arguments, empty issuer/base_url.

=item C<Net::Async::Zitadel::Error::Network>

OIDC endpoint HTTP failures (discovery, JWKS, userinfo, token).

=item C<Net::Async::Zitadel::Error::API>

Management API non-2xx responses. Carries C<http_status> and C<api_message>.

=back

All classes stringify to C<message> for backward compatibility.

=head1 SEE ALSO

L<Net::Async::Zitadel>, L<Net::Async::Zitadel::OIDC>, L<Net::Async::Zitadel::Management>

=cut
