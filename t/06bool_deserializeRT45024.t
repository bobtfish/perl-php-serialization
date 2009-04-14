#!/usr/bin/env perl
use strict;
use warnings;

use PHP::Serialization;
use Test::More tests => 1;

my $s = 'a:4:{i:0;s:3:"ABC";i:1;s:3:"OPQ";i:2;s:3:"XYZ";i:3;b:0;}';
my $u = PHP::Serialization::unserialize($s);
is_deeply $u, [
    'ABC',
    'OPQ',
    'XYZ',
    undef,
];

