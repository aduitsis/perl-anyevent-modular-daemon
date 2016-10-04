package Daemon::Plugin::Processes;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);

use Moose;
use Log::Log4perl;
#use Data::Printer;
#use AnyEvent::Filesys::Notify;
#use File::Basename;
#use File::Spec;
#use Array::Utils qw(unique);
#use Fcntl;
#use Redis;
#use JSON;
use Proc::ProcessTable;

with 'Daemon::Plugin';

my $logger = Log::Log4perl::get_logger();


has callback => (
	is	=> 'ro',
	isa	=> 'Ref',
	writer	=> '_set_callback',
);

has proc_table => (
	is	=> 'ro',
	isa	=> 'Proc::ProcessTable',
	default => sub { Proc::ProcessTable->new },
);

has period => (
	is	=> 'ro',
	isa	=> 'Num',
	default	=> 30,
);

# This is for FreeBSD
my %fields = (
	pid	=> 'pid',
	ppid	=> 'ppid',
	uid	=> 'uid',
	euid	=> 'euid',
	gid	=> 'gid',
	start	=> 'start',
	state	=> 'state',
	fname	=> 'fname',
	vmsize	=> 'vmsize',
	rss	=> 'rss',
);
	

sub BUILD {
	my $self = shift // die 'incorrect call';
	$self->_set_callback(
		AnyEvent->timer(
			interval=> $self->period,
			cb	=> sub {
				for my $proc ($self->proc_table->table->@*){
					$self->trace($proc->pid.' '.$proc->cmndline);
					$self->send_to_next( { ( map { $fields{$_}=>$proc->$_ } (keys %fields) )  }  );
				}
			},
		),
	);
}
		
1;
