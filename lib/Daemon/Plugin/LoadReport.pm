package Daemon::Plugin::LoadReport;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);

use Moose;
use Log::Log4perl;
use BSD::getloadavg;

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

sub BUILD {
	my $self = shift // die 'incorrect call';
	$self->debug("creating periodic load reporter with period ".$self->period);
	$self->_set_callback( AnyEvent->timer(
		interval=> $self->period,
		cb	=> sub {
			my @loadavg = getloadavg();
			$logger->trace("load average is ".join(',',@loadavg));
			$self->send_to_next({ '1' => $loadavg[0] , '5' => $loadavg[1] , '15' => $loadavg[2] });
		},
	));
}

1;
