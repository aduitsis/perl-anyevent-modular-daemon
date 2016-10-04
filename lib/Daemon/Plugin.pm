package Daemon::Plugin;

use v5.20;
use feature 'postderef' ;
no warnings qw(experimental::postderef);
use autodie;

use Log::Log4perl;
use Data::Printer;
use Sub::Install;

use Moose::Role;

my $logger = Log::Log4perl::get_logger();

#all objects have an identifier
has id => (
	is	=> 'ro',
	isa	=> 'Str',
);

# all objects have a dispatch call attribute, which is a coderef
# and will be supplied by somebody outside the object. 
has dispatch => (
        is      => 'ro',
        isa     => 'CodeRef',
);

has next_objects => (
	is	=> 'ro',
	isa	=> 'ArrayRef[Str]',
);

sub send_to_next {
	my $self = shift // die 'incorrect call';
	my $message = shift // die 'incorrect call';
	for my $next_object ( $self->next_objects->@* ) {
		$self->trace("next object: ".$next_object);
		$self->dispatch->($next_object,'receive',$message);
	}
}

for my $subname ( qw(info debug warn trace error fatal ) ) {
	Sub::Install::install_sub( {
		as	=> $subname,
		code	=> sub {
			my $self = shift // die 'incorrect call';
			my $message = shift // die 'incorrect call';
			$logger->$subname($self->id.': '.$message);
		},
	} );
}
	

1;
