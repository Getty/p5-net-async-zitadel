package Net::Async::Zitadel::Error::Validation;

# ABSTRACT: Raised for missing or invalid arguments before any HTTP call

use Moo;
extends 'Net::Async::Zitadel::Error';
use namespace::clean;

1;

__END__

=head1 DESCRIPTION

Subclass of L<Net::Async::Zitadel::Error>. Raised for missing or invalid
arguments (empty issuer/base_url, missing token/client_id, …) before any HTTP
request is made — returned as a failed L<Future>. Inherits the C<message>
attribute and stringification overload from the base class.

=head1 SEE ALSO

L<Net::Async::Zitadel::Error>

=cut
