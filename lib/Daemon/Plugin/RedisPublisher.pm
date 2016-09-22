package Daemon::Plugin::RedisPublisher;

use v5.20;
use feature 'postderef' ; no warnings 'experimental::postderef';
use autodie;

use Moose;
use Log::Log4perl;
use Data::Printer;
use AnyEvent::Filesys::Notify;
use File::Basename;
use File::Spec;
use Array::Utils qw(unique);
use Fcntl;

with 'Daemon::Plugin';

my $logger = Log::Log4perl::get_logger();

sub receive {
	my $self = shift // die 'incorrect call';
	$logger->debug('received message '.$_[0])	
}


1;
