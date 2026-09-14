use strict;
use warnings;
use Test::More;

use_ok('Net::Async::Zitadel');
use_ok('Net::Async::Zitadel::OIDC');
use_ok('Net::Async::Zitadel::Management');
use_ok('Net::Async::Zitadel::Error');
use_ok('Net::Async::Zitadel::Error::Validation');
use_ok('Net::Async::Zitadel::Error::Network');
use_ok('Net::Async::Zitadel::Error::API');

done_testing;
