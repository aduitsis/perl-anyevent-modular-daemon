package Daemon::Plugin::FreeBSDFilesystems;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);

use Moose;
use Log::Log4perl;
use FreeBSD::FsStat;

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
        default => 600,
);

sub BUILD {
	my $self = shift // die 'incorrect call';
	$self->info("creating periodic filesystem reporter with period ".$self->period);
	$self->_set_callback( AnyEvent->timer(
		interval=> $self->period,
		cb	=> sub {
			my @fsystems = FreeBSD::FsStat::get_filesystems();
			for my $fs ( @fsystems ) {
				$self->trace($fs->device.' '.$fs->mountpoint.' '.$fs->pct_avail);
				$self->send_to_next({
					fstype		=> $fs->type,
					device		=> $fs->device,
					mountpoint	=> $fs->mountpoint,
					size		=> $fs->size,
					available	=> $fs->avail,
					pct_avail	=> $fs->pct_avail,
				});
			}
		},
	));
}

1;
