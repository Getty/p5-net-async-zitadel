requires 'Crypt::JWT';
requires 'Future';
requires 'HTTP::Request';
requires 'IO::Async';
requires 'IO::Async::SSL';
requires 'JSON::MaybeXS';
requires 'MIME::Base64';
requires 'Moo';
requires 'namespace::clean';
requires 'Net::Async::HTTP';
requires 'URI';

on test => sub {
    requires 'Crypt::PK::ECC';
    requires 'Crypt::PK::RSA';
    requires 'Test::Exception';
    requires 'Test::More';
};
