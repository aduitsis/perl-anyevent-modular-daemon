package Daemon::Plugin::SendmailParser;

use v5.20;
use feature 'postderef';
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

with 'Daemon::Plugin';

my $logger = Log::Log4perl::get_logger();

sub receive {
        my $self = shift // die 'incorrect call';
        $self->trace($self->id.': received message '.$_[0]);
	$self->parse_line( $_[0] );	

}

sub parse_line {
	my $self = shift // die 'incorrect call';
	my $line = shift // die 'incorrect call';

	$logger->trace($self->id.': line received: '.$line);

	if ( my ($date,$host,$process,$pid,$rest) =
		( $line =~	/
				^(\S+\s+\d+\s+\d+:\d+:\d+)
				\s+
				(\S+)
				\s+
				(\S+?)\[(\d+)\]:
				\s+
				(.*)/x
		)
	) {

		$self->trace(" parsed: date=$date,host=$host,proc=$process,pid=$pid");
		# standard sendmail message with id in front
		if($rest =~ /^([A-Za-z0-9]+): (.*)/) {
                	my ($id,$rest2)=($1,$2); 
                	#if it has a tokenizable content
			my %kv;
			while( $rest2 =~ m/(?<key>\S+?)=(?<value>.+?)(, |$)/g ){
				$kv{$+{key}}=$+{value};
                        }
			# at present, parse only from messages
			if( exists( $kv{from} ) ) {
				$self->trace(join(',',map { "$_=$kv{$_}" } sort keys %kv));
				if( defined( $kv{ relay } ) && ( $kv{ relay } =~ /\[(?<ip>\S+)\]$/ )  ) {
					my $ip = $+{ip};
					$ip =~ s/^IPv6://;
					$self->send_to_next( { host => $host , ip => $ip, nrcpts => $kv{nrcpts}, accept => ( $kv{nrcpts} != 0 )? 1 : 0 } );
				}
			}
                }
	}
	return
}

1;
