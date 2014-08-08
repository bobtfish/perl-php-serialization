#!/usr/bin/env perl

use Test::More tests => 1;

use PHP::Serialization qw(unserialize serialize);

my $encoded = q|O:7:"Foo\\Bar":1:{s:5:"value";i:1;}|;

my $data = unserialize($encoded);
is( ref $data, ref unserialize( serialize( $data )) );

