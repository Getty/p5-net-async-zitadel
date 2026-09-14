package Net::Async::Zitadel::Error::Network;

# ABSTRACT: Raised when an OIDC endpoint HTTP request fails

use Moo;
extends 'Net::Async::Zitadel::Error';
use namespace::clean;

1;

__END__

=head1 DESCRIPTION

Subclass of L<Net::Async::Zitadel::Error>. Raised on OIDC endpoint HTTP failures
(discovery, JWKS, userinfo, token) — returned as a failed L<Future>. Inherits
the C<message> attribute and stringification overload from the base class.

=head1 SEE ALSO

L<Net::Async::Zitadel::Error>

=cut
