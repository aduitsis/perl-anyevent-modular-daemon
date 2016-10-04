package Daemon::Plugin::Printer;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);

use Moose;
use Log::Log4perl;
use Data::Printer;
#use AnyEvent::Filesys::Notify;
#use File::Basename;
#use File::Spec;
#use Array::Utils qw(unique);
#use Fcntl;
#use Redis;
#use JSON;

with 'Daemon::Plugin';

my $logger = Log::Log4perl::get_logger();

sub receive {
	my $self = shift // die 'incorrect call';
	my $msg = shift // die 'incorrect call';
	my $str = p $msg;
	$self->info( $str );
}

1;

