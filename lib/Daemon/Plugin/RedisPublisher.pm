package Daemon::Plugin::RedisPublisher;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);
use autodie;

use Moose;
use Log::Log4perl;
use Data::Printer;
use AnyEvent::Filesys::Notify;
use File::Basename;
use File::Spec;
use Array::Utils qw(unique);
use Fcntl;
use Redis;
use JSON;

with 'Daemon::Plugin';

has redis_str => (
	is		=> 'ro',
	isa		=> 'Str',
	required	=> 1,
	init_arg	=> 'redis',
	writer		=> '_set_redis_str',
	trigger		=> sub { 
		# add a ':6379' at the end of the string if it is not there already
		( $_[1] !~ /:\d+$/ ) and $_[0]->_set_redis_str( $_[0]->redis_str.':6379' )
	},
);

has channel => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> 'generic',
);

my $logger = Log::Log4perl::get_logger();

my $redis;

sub receive {
	my $self = shift // die 'incorrect call';
	my $msg = shift // die 'incorrect call';
	my $json = encode_json( $msg );
	$self->trace("received message $json and will publish to ".$self->channel );
	$redis->publish( $self->channel => $json );	
}

sub BUILD {
	my $self = shift // die 'incorrect call';
	$self->info('connecting to '.$self->redis_str);
	$redis = Redis->new( server => $self->redis_str );
}


1;
