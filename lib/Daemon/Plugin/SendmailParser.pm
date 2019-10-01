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
use Redis;

with 'Daemon::Plugin';

has redis => (
	is	=>	'rw',
	isa	=>	'Redis',
);

has redis_cache => (
        is              => 'ro',
        isa             => 'Str',
        required        => 1,
        init_arg        => 'redis_cache',
        writer          => '_set_redis_str',
        trigger         => sub { 
                # add a ':6379' at the end of the string if it is not there already
                ( $_[1] !~ /:\d+$/ ) and $_[0]->_set_redis_str( $_[0]->redis_cache.':6379' )
        },
);

has redis_ttl => (
	is		=> 'ro',
	isa		=> 'Num',
	default		=> 600,
);

my $logger = Log::Log4perl::get_logger();

sub BUILD {
	my $self = shift // die 'incorrect call';
        $self->init_redis;
}

sub init_redis {
	$_[0]->info('connecting to '.$_[0]->redis_cache);
	$_[0]->redis( Redis->new( server => $_[0]->redis_cache ) );
	$_[0]->debug('Redis TTL set to '.$_[0]->redis_ttl)
}



sub receive {
        my $self = shift // die 'incorrect call';
        $self->trace($self->id.': received message '.$_[0]);
	$self->parse_line( $_[0] );	

}

sub parse_line {
	my $self = shift // die 'incorrect call';
	my $line = shift // die 'incorrect call';
	state $cache;

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
		if( $rest =~ /\s*AUTH=server,\s+(.*)/ ) {
			my $rest2 = $1;
			my %kv;
			while( $rest2 =~ m/(?<key>\S+?)=(?<value>.+?)(, |$)/g ){
				$kv{$+{key}}=$+{value};
                        }
			# Jun  4 11:41:12 hostname sm-mta[47019]: AUTH=server, relay=[IPv6:aaaa::bbbb], authid=whatever, mech=LOGIN, bits=0
			if( exists( $kv{relay} ) && exists( $kv{authid} ) && defined( $kv{ relay } ) && ( $kv{ relay } =~ /\[(?<ip>\S+)\]$/ ) ) {
				my $ip = $+{ip}; $ip =~ s/^IPv6://;
				my $authid = lc $kv{authid};
				my $key = join(':','smtpauth',$host,$pid,$ip);
				$self->trace( "authid $authid cached with: ".$key );
				$self->redis->hset($key, authid => lc $kv{authid});
				$self->redis->expire($key,$self->redis_ttl);
			}
		}
		# standard sendmail message with id in front
		elsif($rest =~ /^([A-Za-z0-9]+): (.*)/) {
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
					$kv{ from } =~ s/^<//;
					$kv{ from } =~ s/>$//;
					# match possible authid
					my $authidkey = join(':','smtpauth',$host,$pid,$ip);
					my $authid = undef;
					if( $self->redis->exists( $authidkey ) ) {
						my %ret = $self->redis->hgetall( $authidkey );
						$authid = $ret{ authid };
						$self->debug("user ".$authid." sends with from=".$kv{ from })
					}
					# construct the message
					my %msg = (
						msgid	=> $id,
						host	=> $host,
						ip	=> $ip,
						nrcpts	=> int( $kv{nrcpts} ),
						accept	=> ( $kv{nrcpts} != 0 )? 1 : 0,
						size	=> int( $kv{ size } ),
						from	=> lc $kv{ from },
					);
					$msg{ authid } = $authid if defined( $authid );

					$self->send_to_next( {
						%msg,
						outgoing=> 0,
					});
					if( $kv{nrcpts} != 0 ) {
						my $key = 'sendmail:'.$id;
						$msg{ authid } = $authid if defined( $authid );
						$self->redis->hset($key, %msg );
						$self->redis->expire($key,$self->redis_ttl);
					}
				}
			}
			elsif( exists( $kv{ to } ) ) {
				$self->trace('TO:'.join(',',map { "$_=$kv{$_}" } sort keys %kv));
				$kv{ to } =~ s/<//;
				$kv{ to } =~ s/>//;
				my @tos=split(',',$kv{ to });
				for my $to ( @tos ) {
					if( defined( $kv{ relay } ) ) {
						my $key = 'sendmail:'.$id;
						my %msg = (
							msgid	=> $id,
							host	=> $host,
							relay	=> $kv{ relay },
							dsn	=> $kv{ dsn },	
							to	=> $to,
							stat	=> $kv{ stat },
							outgoing=> 1,
						);
						# redis key exists
						if( $self->redis->exists( $key ) ) {
							my %from = $self->redis->hgetall( $key );
							$self->redis->hmset( $key, 
								relay	=> $kv{ relay },
								dsn	=> $kv{ dsn },	
								to	=> $kv{ to },
								stat	=> $kv{ stat },
							);
							if( $from{ host } ne $host ) {
								$self->warn("mismatch between ".$from{ host }.' and '.$host.' for '.$id);
							}
							if( $from{ authid } ) {
								$msg{ authid } = $from{ authid }
							}
							$self->send_to_next( {
								%msg,
								from	=> $from{ from },
								size	=> $from{ size },	
								nrcpts	=> $from{ nrcpts},
								ip	=> $from{ ip },
							});
						}
						else {
							$self->send_to_next( { %msg } );
						}
					}
				}
			}
			#else {
			#	$self->info('ELSE:'.join(',',map { "$_=$kv{$_}" } sort keys %kv));
			#}
                }
	}
	return
}

1;
