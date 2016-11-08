package Daemon::Plugin::LoadReport;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);

use Moose;
use Log::Log4perl;
use BSD::getloadavg;

use Sys::Hostname;

with 'Daemon::Plugin';

my $logger = Log::Log4perl::get_logger();

has callback => (
        is      => 'ro',
        isa     => 'Ref',
        writer  => '_set_callback',
);

has period => (
        is      => 'ro',
        isa     => 'Num',
        default => 30,
);

has type => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> 'load',
);

has index => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> 'omnidisco',
);

has host_name => (
	is	=> 'ro',
	isa	=> 'Str',
	default	=> sub { hostname },
);


sub BUILD {
	my $self = shift // die 'incorrect call';
	$self->debug("creating periodic load reporter with period ".$self->period);
	$self->_set_callback( AnyEvent->timer(
		interval=> $self->period,
		cb	=> sub {
			my @loadavg = getloadavg();
			$logger->trace("load average is ".join(',',@loadavg));
			$self->send_to_next({
				'@metadata' => {
					time	=> time,
					type	=> $self->type,
					index	=> $self->index,
				},
				one	=> $loadavg[0],
				five	=> $loadavg[1],
				fifteen => $loadavg[2],
				system	=> $self->host_name,
			});
		},
	));
}

1;
