package Net::Async::Zitadel::Management;

# ABSTRACT: Async client for Zitadel Management API v1

use Moo;
use JSON::MaybeXS qw(encode_json decode_json);
use HTTP::Request;
use URI;
use Future;
use namespace::clean;

our $VERSION = '0.001';

has base_url => (
    is       => 'ro',
    required => 1,
);

has token => (
    is       => 'ro',
    required => 1,
);

has http => (
    is       => 'ro',
    required => 1,
    doc      => 'Net::Async::HTTP instance (shared from parent)',
);

has _api_base => (
    is      => 'lazy',
    builder => sub {
        my $base = $_[0]->base_url;
        $base =~ s{/+$}{};
        "$base/management/v1";
    },
);

# --- Generic async request methods ---

sub _request_f {
    my ($self, $method, $path, $body) = @_;

    my $url = $self->_api_base . $path;
    my $req = HTTP::Request->new($method => $url);
    $req->header(Authorization => 'Bearer ' . $self->token);
    $req->header(Accept        => 'application/json');

    if ($body) {
        $req->header('Content-Type' => 'application/json');
        $req->content(encode_json($body));
    }

    return $self->http->do_request(request => $req)->then(sub {
        my ($response) = @_;
        my $data;
        if ($response->decoded_content && length $response->decoded_content) {
            eval { $data = decode_json($response->decoded_content) };
        }

        unless ($response->is_success) {
            my $msg = "API error: " . $response->status_line;
            if ($data && $data->{message}) {
                $msg .= " - $data->{message}";
            }
            return Future->fail("$msg\n");
        }

        return Future->done($data // {});
    });
}

sub _get_f    { $_[0]->_request_f('GET',    $_[1]) }
sub _post_f   { $_[0]->_request_f('POST',   $_[1], $_[2]) }
sub _put_f    { $_[0]->_request_f('PUT',    $_[1], $_[2]) }
sub _delete_f { $_[0]->_request_f('DELETE', $_[1]) }

# --- Users ---

sub list_users_f {
    my ($self, %args) = @_;
    $self->_post_f('/users/_search', {
        query => {
            offset => $args{offset} // 0,
            limit  => $args{limit}  // 100,
            asc    => $args{asc}    // JSON::MaybeXS::true,
        },
        $args{queries} ? (queries => $args{queries}) : (),
    });
}

sub get_user_f {
    my ($self, $user_id) = @_;
    die "user_id required\n" unless $user_id;
    $self->_get_f("/users/$user_id");
}

sub create_human_user_f {
    my ($self, %args) = @_;
    $self->_post_f('/users/human', {
        userName => $args{user_name} // die("user_name required\n"),
        profile  => {
            firstName   => $args{first_name} // die("first_name required\n"),
            lastName    => $args{last_name}  // die("last_name required\n"),
            displayName => $args{display_name} // "$args{first_name} $args{last_name}",
            $args{nick_name}          ? (nickName          => $args{nick_name})          : (),
            $args{preferred_language} ? (preferredLanguage => $args{preferred_language}) : (),
        },
        email => {
            email           => $args{email} // die("email required\n"),
            isEmailVerified => $args{email_verified} // JSON::MaybeXS::false,
        },
        $args{phone} ? (phone => {
            phone           => $args{phone},
            isPhoneVerified => $args{phone_verified} // JSON::MaybeXS::false,
        }) : (),
        $args{password} ? (password => $args{password}) : (),
    });
}

sub update_user_f {
    my ($self, $user_id, %args) = @_;
    die "user_id required\n" unless $user_id;
    $self->_put_f("/users/$user_id/profile", {
        $args{first_name}   ? (firstName   => $args{first_name})   : (),
        $args{last_name}    ? (lastName    => $args{last_name})    : (),
        $args{display_name} ? (displayName => $args{display_name}) : (),
        $args{nick_name}    ? (nickName    => $args{nick_name})    : (),
    });
}

sub deactivate_user_f {
    my ($self, $user_id) = @_;
    die "user_id required\n" unless $user_id;
    $self->_post_f("/users/$user_id/_deactivate", {});
}

sub reactivate_user_f {
    my ($self, $user_id) = @_;
    die "user_id required\n" unless $user_id;
    $self->_post_f("/users/$user_id/_reactivate", {});
}

sub delete_user_f {
    my ($self, $user_id) = @_;
    die "user_id required\n" unless $user_id;
    $self->_delete_f("/users/$user_id");
}

# --- Projects ---

sub list_projects_f {
    my ($self, %args) = @_;
    $self->_post_f('/projects/_search', {
        query => {
            offset => $args{offset} // 0,
            limit  => $args{limit}  // 100,
        },
        $args{queries} ? (queries => $args{queries}) : (),
    });
}

sub get_project_f {
    my ($self, $project_id) = @_;
    die "project_id required\n" unless $project_id;
    $self->_get_f("/projects/$project_id");
}

sub create_project_f {
    my ($self, %args) = @_;
    $self->_post_f('/projects', {
        name => $args{name} // die("name required\n"),
        $args{project_role_assertion}   ? (projectRoleAssertion   => $args{project_role_assertion})   : (),
        $args{project_role_check}       ? (projectRoleCheck       => $args{project_role_check})       : (),
        $args{has_project_check}        ? (hasProjectCheck        => $args{has_project_check})        : (),
        $args{private_labeling_setting} ? (privateLabelingSetting => $args{private_labeling_setting}) : (),
    });
}

sub update_project_f {
    my ($self, $project_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    $self->_put_f("/projects/$project_id", {
        name => $args{name} // die("name required\n"),
        $args{project_role_assertion}   ? (projectRoleAssertion   => $args{project_role_assertion})   : (),
        $args{project_role_check}       ? (projectRoleCheck       => $args{project_role_check})       : (),
        $args{has_project_check}        ? (hasProjectCheck        => $args{has_project_check})        : (),
        $args{private_labeling_setting} ? (privateLabelingSetting => $args{private_labeling_setting}) : (),
    });
}

sub delete_project_f {
    my ($self, $project_id) = @_;
    die "project_id required\n" unless $project_id;
    $self->_delete_f("/projects/$project_id");
}

# --- Applications (OIDC) ---

sub list_apps_f {
    my ($self, $project_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    $self->_post_f("/projects/$project_id/apps/_search", {
        query => {
            offset => $args{offset} // 0,
            limit  => $args{limit}  // 100,
        },
        $args{queries} ? (queries => $args{queries}) : (),
    });
}

sub get_app_f {
    my ($self, $project_id, $app_id) = @_;
    die "project_id required\n" unless $project_id;
    die "app_id required\n" unless $app_id;
    $self->_get_f("/projects/$project_id/apps/$app_id");
}

sub create_oidc_app_f {
    my ($self, $project_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    $self->_post_f("/projects/$project_id/apps/oidc", {
        name                  => $args{name} // die("name required\n"),
        redirectUris          => $args{redirect_uris} // die("redirect_uris required\n"),
        responseTypes         => $args{response_types} // ['OIDC_RESPONSE_TYPE_CODE'],
        grantTypes            => $args{grant_types} // ['OIDC_GRANT_TYPE_AUTHORIZATION_CODE'],
        appType               => $args{app_type} // 'OIDC_APP_TYPE_WEB',
        authMethodType        => $args{auth_method} // 'OIDC_AUTH_METHOD_TYPE_BASIC',
        $args{post_logout_uris}        ? (postLogoutRedirectUris => $args{post_logout_uris})        : (),
        $args{dev_mode}                ? (devMode                => $args{dev_mode})                : (),
        $args{access_token_type}       ? (accessTokenType        => $args{access_token_type})       : (),
        $args{id_token_role_assertion} ? (idTokenRoleAssertion   => $args{id_token_role_assertion}) : (),
    });
}

sub update_oidc_app_f {
    my ($self, $project_id, $app_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    die "app_id required\n" unless $app_id;
    $self->_put_f("/projects/$project_id/apps/$app_id/oidc_config", \%args);
}

sub delete_app_f {
    my ($self, $project_id, $app_id) = @_;
    die "project_id required\n" unless $project_id;
    die "app_id required\n" unless $app_id;
    $self->_delete_f("/projects/$project_id/apps/$app_id");
}

# --- Organizations ---

sub get_org_f {
    my ($self) = @_;
    $self->_get_f('/orgs/me');
}

# --- Roles ---

sub add_project_role_f {
    my ($self, $project_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    $self->_post_f("/projects/$project_id/roles", {
        roleKey     => $args{role_key} // die("role_key required\n"),
        displayName => $args{display_name} // $args{role_key},
        $args{group} ? (group => $args{group}) : (),
    });
}

sub list_project_roles_f {
    my ($self, $project_id, %args) = @_;
    die "project_id required\n" unless $project_id;
    $self->_post_f("/projects/$project_id/roles/_search", {
        query => {
            offset => $args{offset} // 0,
            limit  => $args{limit}  // 100,
        },
        $args{queries} ? (queries => $args{queries}) : (),
    });
}

# --- User Grants (role assignments) ---

sub create_user_grant_f {
    my ($self, %args) = @_;
    my $user_id = $args{user_id} // die "user_id required\n";
    $self->_post_f("/users/$user_id/grants", {
        projectId  => $args{project_id} // die("project_id required\n"),
        roleKeys   => $args{role_keys}  // die("role_keys required\n"),
    });
}

sub list_user_grants_f {
    my ($self, %args) = @_;
    $self->_post_f('/users/grants/_search', {
        query => {
            offset => $args{offset} // 0,
            limit  => $args{limit}  // 100,
        },
        $args{queries} ? (queries => $args{queries}) : (),
    });
}

1;

__END__

=head1 SYNOPSIS

    use IO::Async::Loop;
    use Net::Async::Zitadel;

    my $loop = IO::Async::Loop->new;
    my $z = Net::Async::Zitadel->new(
        issuer => 'https://zitadel.example.com',
        token  => $personal_access_token,
    );
    $loop->add($z);

    # Users
    my $users = $z->management->list_users_f(limit => 50)->get;
    my $user  = $z->management->create_human_user_f(
        user_name  => 'alice',
        first_name => 'Alice',
        last_name  => 'Smith',
        email      => 'alice@example.com',
    )->get;

    # Projects
    my $projects = $z->management->list_projects_f->get;

    # OIDC Applications
    my $app = $z->management->create_oidc_app_f($project_id,
        name          => 'Web Client',
        redirect_uris => ['https://app.example.com/callback'],
    )->get;

    # Roles & Grants
    $z->management->add_project_role_f($project_id,
        role_key => 'admin',
    )->get;

    $z->management->create_user_grant_f(
        user_id    => $user_id,
        project_id => $project_id,
        role_keys  => ['admin'],
    )->get;

=head1 DESCRIPTION

Async client for the Zitadel Management API v1, built on L<Net::Async::HTTP>
and L<Future>. All methods return L<Future> objects (C<_f> suffix convention).

Mirrors the API surface of L<WWW::Zitadel::Management> but with non-blocking
HTTP via L<Net::Async::HTTP>.

=attr base_url

Required. The Zitadel instance URL.

=attr token

Required. Personal Access Token for authenticating with the Management API.

=attr http

Required. A L<Net::Async::HTTP> instance (typically shared from L<Net::Async::Zitadel>).

=method list_users_f

=method get_user_f

=method create_human_user_f

=method update_user_f

=method deactivate_user_f

=method reactivate_user_f

=method delete_user_f

User CRUD operations. All return Futures.

=method list_projects_f

=method get_project_f

=method create_project_f

=method update_project_f

=method delete_project_f

Project CRUD operations. All return Futures.

=method list_apps_f

=method get_app_f

=method create_oidc_app_f

=method update_oidc_app_f

=method delete_app_f

OIDC application management. All return Futures.

=method get_org_f

Returns a Future resolving to the current organization.

=method add_project_role_f

=method list_project_roles_f

Role management. All return Futures.

=method create_user_grant_f

=method list_user_grants_f

User grant (role assignment) management. All return Futures.

=head1 SEE ALSO

L<Net::Async::Zitadel>, L<WWW::Zitadel::Management>, L<Future>

=cut
