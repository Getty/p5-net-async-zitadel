requires 'Moo';
requires 'Net::Async::HTTP';
requires 'IO::Async';
requires 'Future';
requires 'JSON::MaybeXS';
requires 'Crypt::JWT';
requires 'HTTP::Request';
requires 'MIME::Base64';
requires 'URI';
requires 'namespace::clean';

on test => sub {
    requires 'Test::More';
    requires 'Test::Exception';
    requires 'Crypt::PK::RSA';
    requires 'Crypt::PK::ECC';
};
