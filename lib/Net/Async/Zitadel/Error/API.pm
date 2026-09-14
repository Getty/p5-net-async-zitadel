package Net::Async::Zitadel::Error::API;

# ABSTRACT: Raised when the Management API returns a non-2xx response

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

=head1 DESCRIPTION

Subclass of L<Net::Async::Zitadel::Error>. Raised when the Management API returns
a non-2xx response. In addition to the inherited C<message> attribute and
stringification overload, it carries C<http_status> and C<api_message>.

=head1 SEE ALSO

L<Net::Async::Zitadel::Error>

=cut
