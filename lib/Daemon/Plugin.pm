package Daemon::Plugin;

use v5.20;
use feature 'postderef' ; no warnings 'experimental::postderef';
use autodie;

use Moose::Role;

has dispatch => (
        is      => 'ro',
        isa     => 'CodeRef',
);

1;
