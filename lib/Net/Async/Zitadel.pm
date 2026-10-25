package Net::Async::Zitadel;

# ABSTRACT: Async Perl client for Zitadel identity management (IO::Async + Future)

use Moo;
use Net::Async::HTTP;
use Net::Async::Zitadel::OIDC;
use Net::Async::Zitadel::Management;
use Net::Async::Zitadel::Error;
use namespace::clean;

extends 'IO::Async::Notifier';

our $VERSION = '0.002';

# IO::Async::Notifier is a non-Moo parent: its new() hands every constructor
# key to configure(), which croaks on keys it does not recognise. Strip our
# own attributes here so only genuine notifier params reach the parent. Moo
# still sets the attributes from the original args, and BUILD validates them.
sub FOREIGNBUILDARGS {
    my ($class, %args) = @_;
    delete @args{qw(issuer token http)};
    return %args;
}

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

has token => (
    is  => 'ro',
    doc => 'Personal Access Token for Management API',
);

has http => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        # Net::Async::HTTP has no default timeout, so a server that never
        # answers would leave every Future pending. Redirects are off: none
        # is expected from Zitadel, and a followed one would resend the
        # Authorization header. fail_on_error stays off because the clients
        # turn non-2xx responses into typed errors themselves.
        my $http = Net::Async::HTTP->new(
            user_agent     => 'Net-Async-Zitadel/' . ($self->VERSION // '0'),
            timeout        => 30,
            max_redirects  => 0,
            fail_on_error  => 0,
        );
        $self->add_child($http);
        return $http;
    },
);

has oidc => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        Net::Async::Zitadel::OIDC->new(
            issuer => $self->issuer,
            http   => $self->http,
        );
    },
);

has management => (
    is      => 'lazy',
    builder => sub {
        my $self = shift;
        die Net::Async::Zitadel::Error::Validation->new(
            message => 'Management API requires a token',
        ) unless $self->token;
        Net::Async::Zitadel::Management->new(
            base_url => $self->issuer,
            token    => $self->token,
            http     => $self->http,
        );
    },
);

1;

__END__

=head1 SYNOPSIS

    use IO::Async::Loop;
    use Net::Async::Zitadel;

    my $loop = IO::Async::Loop->new;

    my $z = Net::Async::Zitadel->new(
        issuer => 'https://zitadel.example.com',
        token  => $ENV{ZITADEL_PAT},
    );
    $loop->add($z);

    # OIDC - verify tokens asynchronously
    my $claims = $z->oidc->verify_token_f($access_token)->get;

    # Management API - list users
    my $users = $z->management->list_users_f(limit => 20)->get;

=head1 DESCRIPTION

Net::Async::Zitadel is an asynchronous Perl client for Zitadel, the open-source
identity management platform. It wraps the L<WWW::Zitadel> API surface with
L<Net::Async::HTTP> for non-blocking HTTP and L<Future>-based return values.

Built on L<IO::Async::Notifier>, it integrates naturally into any IO::Async
event loop.

=over 4

=item * B<Async OIDC Client> - Token verification via JWKS, discovery endpoint,
userinfo. All methods return Futures.

=item * B<Async Management API Client> - CRUD operations for users, projects,
applications, and organizations. All methods return Futures.

=back

=attr issuer

Required issuer URL, for example C<https://zitadel.example.com>.

=attr token

Optional Personal Access Token (PAT). Required only when using
L</management>.

=attr http

Lazy-built L<Net::Async::HTTP> instance, added as a child notifier. The
default client is built with C<timeout =E<gt> 30> (seconds per request),
C<max_redirects =E<gt> 0> (a redirect is returned as the response, never
followed, so the C<Authorization> header is not resent) and
C<fail_on_error =E<gt> 0> (non-2xx responses reach the clients, which raise
typed errors). Pass your own C<http> to change any of this.

=attr oidc

Lazy-built L<Net::Async::Zitadel::OIDC> client.

=attr management

Lazy-built L<Net::Async::Zitadel::Management> client. Dies if C<token>
is missing.

=head1 SEE ALSO

L<WWW::Zitadel>, L<Net::Async::Zitadel::OIDC>, L<Net::Async::Zitadel::Management>,
L<IO::Async>, L<Future>

=cut
