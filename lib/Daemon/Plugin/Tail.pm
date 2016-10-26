package Daemon::Plugin::Tail;

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
use Try::Tiny;
use List::Util qw(any);

with 'Daemon::Plugin';

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

has retry_period => (
	is	=> 'ro',
	isa	=> 'Num',
	default	=> 5,
);

has retry_callback => (
	is	=> 'ro',
	isa	=> 'Maybe[Ref]', #maybe means undef is also acceptable
	writer	=> '_set_retry_callback',
);


sub get_unique_directories {
	# linux and freebsd are the same for the time being
	# we are watching entire directories, which may not be optimal
	if( $^O eq 'linux' ) {
		return unique map { File::Spec->rel2abs( dirname( $_ ) ) } $_[0]->filenames->@*
	}
	elsif( $^O eq 'freebsd' ) {
		return unique map { File::Spec->rel2abs(  $_ ) } $_[0]->filenames->@*
	}
	else {
		$logger->fatal("Warning, this module does not support $^O yet");
		die;
	}
}

# this hash may as well be shared amongst all objects of this class
# the keys are filenames and the values are the sizes of those files
# so, no danger of messing the hash between different objects
my %size;

sub open_file {
	my $self =	shift // die 'incorrect call';
	my $filename =	shift // die 'incorrect call';
	my $fh;
	# if filename exists
	try {
		if(-e $filename) {
			$self->debug("opening $filename");
			open $fh,'<',$filename;
			seek $fh,0,Fcntl::SEEK_END;#go to eof
			$self->filehandles->{$filename} = $fh;
			$size{ $filename } = file_size( $fh );
		}
		else {
			$self->debug("$filename does not exist");
			$self->filehandles->{$filename} = undef;
		}
	}
	catch {
		$self->warn("cannot open $filename: ".$_);
		$self->filehandles->{$filename} = undef;
	};
}


sub close_file {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	if( defined( $self->filehandles->{$filename} ) ) {
		$self->debug("closing handle for $filename");
		close $self->filehandles->{$filename};
		$self->filehandles->{$filename} = undef
	}
	else {
		$self->debug("$filename was not open in the first place, nothing to do");
	}
	$self->BUILD;
}

sub file_size {
	(stat($_[0]))[7]
}

sub read_file {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	my $fh = $self->filehandles->{$filename};
	if( ! defined($fh) ) {
		$self->fatal("error! attempt to read from undef filehandle for $filename");
		return
	}
	else {
		my $size = file_size( $fh );
		$self->trace("$filename is $size bytes");
		# compare current with previous size
		if( $size < $size{ $filename } ) {
			$self->debug("$filename truncated, size diminished");
			seek $fh,0,Fcntl::SEEK_SET;#go to start of file
		}
		# now record current size
		$size{ $filename } = $size;

		# now read as many lines as possible
		while( my $line = <$fh> ) {
			if(!defined($line)){
				$self->trace("trying to read from $filename returned undef, eof probably reached");
			}
			else {
				chomp($line);
				$self->trace("$filename read: $line");
				# we have a line, send it to other objects
				$self->send_to_next( $line );
			}
		}
		# the file may also have been deleted
		$self->detect_deletion( $filename )
	}
}

sub detect_deletion {
	my $self = shift // die 'incorrect call';
	my $filename = shift // die 'incorrect call';
	my $fh = $self->filehandles->{$filename};
	# AnyEvent::FileSys::Notify with KQueue backend will erroneously report
	# a file modification when the file has been rotated by newsyslog. The IO::KQueue
	# correctly reports the deletion, but A:F:N does not detect it. This is because
	# newsyslog will instantaneously replace the file, so, looking at the filesystem
	# will not show that something is missing
	use POSIX qw(fstat);
	my ( $dev1, $ino1 ) = fstat( $fh );
	my ( $dev2, $ino2 ) = stat( $filename );
	if( ( $dev1 != $dev2 ) || ( $ino1 != $ino2 ) ) {
		$self->debug("$filename deleted, inode number changed");
		$self->close_file( $filename );
	}
}


sub handle_event {
	my $self = shift // die 'incorrect call';
	my $event = shift // die 'incorrect call';
	my $modified_file = $event->path;
	my $type = $event->type;
	#if( exists $self->filehandles->{ $modified_file } ) { #exists and is defined
	if( any { $_ eq $modified_file } $self->filenames->@* ) { #modified file is in our watchlist
		$self->trace($event->type." event on $modified_file");
		if( $type eq 'created' ) {
			$self->open_file( $modified_file )
		}
		elsif( $type eq 'deleted' ) {
			$self->close_file( $modified_file )
		}
		elsif( $type eq 'modified' ) {
			$self->read_file( $modified_file )
		}
		else {
			$self->fatal("Cannot handle an event of type $type for ".$modified_file);
		}
	}
	else {
		$self->trace("$modified_file not on our watchlist");
	}
}

sub retry_if_not_all_files_open {
	my $self = shift // die 'incorrect call';
	for my $filename ($self->filenames->@*) {
		if ( ! defined( $self->filehandles->{ $filename } ) ) {
			$self->debug("$filename is not open ... will retry in ".$self->retry_period);
			$self->_set_retry_callback( 
				AnyEvent->timer(
					after	=> $self->retry_period,
					cb	=> sub {
						$self->BUILD
					},
				),
			);
			# if we have entered this loop, no need to try everything
			return;
		}
	}
	# if we have made it here without returning, we can reset the callback
	$self->_set_retry_callback(undef);
}

			

sub BUILD {
	my $self = shift // die 'incorrect call';

	# unique directories we must monitor
	my @dirs = $self->get_unique_directories;
	$self->info('initializing, files/dirs to watch: '.join(' ',@dirs));

	# try to open all our filenames
	for my $filename ($self->filenames->@*) {
		next if defined $self->filehandles->{ $filename };
		$self->open_file( $filename )
		
	}

	 $self->_set_callback( 
		AnyEvent::Filesys::Notify->new(
			dirs     => \@dirs,
			cb       => sub {
				my (@events) = @_;
				$self->handle_event( $_ ) for @events;
			},
			parse_events => 1,
		)
	);
	
	$self->retry_if_not_all_files_open;
}


1;
