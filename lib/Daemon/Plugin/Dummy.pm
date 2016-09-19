package Daemon::Plugin::Dummy;

use v5.22;
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

my $logger = Log::Log4perl::get_logger();

has 'filenames' => (
	is	=> 'ro',
	isa	=> 'ArrayRef[Str]',
);


has 'callback' => (
	is	=> 'ro',
	isa	=> 'Object',
	writer	=> '_set_callback',
);

has filehandles => (
	is	=> 'ro',
	isa	=> 'HashRef[FileHandle]',
	default	=> sub { {} },
);

sub filehandle {
	open my $fh, '-|','tail -F -n0 -q '.$_[0]->filename;
	return $fh
}

sub get_unique_directories {
	unique map { File::Spec->rel2abs( dirname( $_ ) ) } $_[0]->filenames->@*
}

my %size;

sub open_file {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	my $fh;
	if(-e $filename) {
		$logger->debug("opening $filename");
		open $fh,'<',$filename;
		seek $fh,0,Fcntl::SEEK_END;#go to eof
		$self->filehandles->{$filename} = $fh;
		$size{ $filename } = (stat($fh))[7];
	}
	else {
		$logger->debug("$filename does not exist");
		$self->filehandles->{$filename} = undef
	}
}


sub close_file {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	if( defined( $self->filehandles->{$filename} ) ) {
		$logger->debug("closing handle for $filename");
		close $self->filehandles->{$filename};
		$self->filehandles->{$filename} = undef
	}
	else {
		$logger->debug("$filename was not open, nothing to do");
	}
}

sub read_file {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	my $fh = $self->filehandles->{$filename};
	if(!defined($fh)) {
		$logger->fatal("error! $filename attempt to read from undefined filehandle");
		$self->close_file( $filename );
		return
	}
	else {
		my $size = (stat($fh))[7];
		$logger->debug("$filename is $size bytes");
		if( $size < $size{ $filename } ) {
			$logger->debug("$filename truncated");
			seek $fh,0,Fcntl::SEEK_SET;#go to start of file
		}
		$size{ $filename } = $size;
		while( my $line = <$fh> ) {
			if(!defined($line)){
				$logger->debug("trying to read from $filename returned undef");
			}
			else {
				chomp($line);
				$logger->debug("line read: $line");
			}
		}
	}
}


sub handle_event {
	my $self = shift // die 'incorrect call';
	my $event = shift // die 'incorrect call';
	my $modified_file = $event->path;
	my $type = $event->type;
	if( exists $self->filehandles->{ $modified_file } ) { #exists and is defined
		$logger->debug($event->type." event on $modified_file");
		if( $type eq 'created' ) {
			$self->open_file( $modified_file )
		}
		elsif( $type eq 'deleted' ) {
			$self->close_file( $modified_file )
		}
		elsif( $type eq 'modified' ) {
			$self->read_file( $modified_file )
		}
	}
}

sub BUILD {
	my $self = shift // die 'incorrect call';
	my @dirs = $self->get_unique_directories;
	$logger->info('Directories to watch: '.join(',',@dirs));
	#open my $fh , '-|','tail -F -n0 -q /var/tmp/whatever.log';
	#my $io = AnyEvent->io(
	#		fh		=> $fh,
	#		poll		=> 'r',
	#		cb		=> sub {
	#			$logger->debug("eof=".eof($fh));
	#			chomp (my $input = <$fh>);
	#			$logger->info($input)
	#		},
	#);
	#$_[0]->_set_callback( $io );

	for my $filename ($self->filenames->@*) {
		$self->open_file( $filename )
	}

	p $self->filehandles;

	my $notifier = AnyEvent::Filesys::Notify->new(
		dirs     => \@dirs,
		cb       => sub {
			my (@events) = @_;
			### p @events;
			$self->handle_event( $_ ) for @events;
		},
		parse_events => 1,
	);
	$self->_set_callback( $notifier );
}


1;
