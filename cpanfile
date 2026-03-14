requires 'Moo';
requires 'Net::Async::HTTP';
requires 'IO::Async';
requires 'Future';
requires 'Future::AsyncAwait';
requires 'JSON::MaybeXS';
requires 'Crypt::JWT';
requires 'URI';
requires 'MIME::Base64';
requires 'namespace::clean';

on test => sub {
    requires 'Test::More';
    requires 'Test::Exception';
};
