#!/usr/bin/perl

use strict;
use warnings;

use Sys::Hostname;
use IO::Socket;

use JSON;

use lib '/usr/lib/vmon';
use common;

# We enable force flush
$| = 1;



#################################################
#   Global settings                             #
#################################################

my $VMON_VERSION = '1.0';

my $CONFIG_FILE = '/etc/vmon/vmon.config';

# The logfile
my $LOGFILE = '/var/log/vmon-responder.log';

# The port on which to listen network requests
my $TCP_PORT = undef;

# Where the results from the probes are stored
my $PROBES_RESULTS_PATH = undef;



#################################################
#   Main program                                #
#################################################



# We first change the STDOUT filehandle
close( STDOUT );
open( STDOUT, '>>', $LOGFILE ) or die( "Can't send STDOUT to the logfile '$LOGFILE'\n" );

# We then change the STDERR filehandle (if the operation fails, we print an error on STDOUT - if we die, nothing will be sent to STDERR)
close( STDERR );
if( not open( STDERR, '>>', $LOGFILE ) )
{
    common::printLog( "Can't send STDERR to the logfile '$LOGFILE'\n" );
    exit( 1 );
}



common::printLog( "Starting vmon v.$VMON_VERSION...\n" );

# We load the config
_loadConfig( );

my $hostname = Sys::Hostname::hostname( );

my $socket = new IO::Socket::INET( 'LocalHost' => $hostname, 'LocalPort' => $TCP_PORT, 'Proto' => 'tcp', 'Listen' => 1, 'Reuse' => 1 );
not $socket and die( "Can't create socket on port '$TCP_PORT' because of: $!\n" );

common::printLog( "vmon is listening on $hostname:$TCP_PORT...\n" );



# This will memorize the highest status
my $serverStatus = 0;

while( 1 )
{
    my $socket_connection = $socket->accept( );

    # This will held all results
    my $resultsHash = { };

    # We then send back the probes results on request
    opendir( DIR, $PROBES_RESULTS_PATH ) or die( "Can't open the probes results directory at '$PROBES_RESULTS_PATH' because of: $!\n" );
    my @files = readdir( DIR );
    closedir( DIR );

    # We check each result and we send back only those which are not OK
    foreach my $result( @files )
    {
        $result eq '.'  and next;
        $result eq '..' and next;

        my $resultFile = "$PROBES_RESULTS_PATH/$result";

        open( RESULT, '<', $resultFile ) or die( "Can't open the result file '$resultFile'\n" );
        my @resultContent = <RESULT>;
        close( RESULT );

        chomp( @resultContent );

        # The first line contains the status, the other ones the additional informations
        my $probeStatus = shift( @resultContent ) || 999;

        $probeStatus > $serverStatus and $serverStatus = $probeStatus;

        # We also retrieve the last modification date
        my @months = qw{ January February March April May June July August September October November December };

        my $lastModificationTimestamp = ( stat $resultFile )[ 9 ];
        my @lastModificationDate = localtime( $lastModificationTimestamp );

        # We add all the informations in the hash
        $resultsHash->{ $result } =
        {
            'status'            => $probeStatus,
            'infos'             => \@resultContent,
            'lastModification'  =>
            {
                'timestamp' => $lastModificationTimestamp,
                'date'      => "$months[ $lastModificationDate[ 4 ] ] $lastModificationDate[ 3 ], " . ( 1900 + $lastModificationDate[ 5 ] ) . " - $lastModificationDate[ 2 ]:$lastModificationDate[ 1 ]:" . ( length( $lastModificationDate[ 0 ] ) > 1 ? $lastModificationDate[ 0 ] : "0$lastModificationDate[ 0 ]" )
            }
        };
    }

    # We add the global status (the highest of all statuses)
    $resultsHash->{ 'server_global' } = { 'status' => $serverStatus };

    # We now build a JSON out of the hash
    my $json = JSON::encode_json( $resultsHash );

    # And we send it back
    print $socket_connection "$json\n";

    close( $socket_connection );
}



# This will load the config file, set the global parameters and redirect STDOUT and STDERR to the logfile
sub _loadConfig
{
    # We first load the configuration
    common::printLog( "Loading config file at '$CONFIG_FILE'...\n" );
    open( CONFIG, '<', $CONFIG_FILE ) or die( "Can't load the config file $CONFIG_FILE because of: $!\n" );
    my @config = <CONFIG>;
    close( CONFIG );

    chomp( @config );

    # We look for needed parameters
    foreach my $line( @config )
    {
        $line =~ m|^#|      and next;
        $line =~ m|^\s*$|   and next;

        if( $line =~ m|^tcp_port\s*=\s*(.*?)$| )
        {
            my $port = $1;

            $port !~ m|^[0-9]+$| and die( "The port '$port' is not an integer" );

            if( ( $port < 1 ) or ( $port > 65535 ) )
            {
                die( "The port '$port' is not a valid port\n" );
            }

            $TCP_PORT = $port;
        }
        elsif( $line =~ m|^probes_results_path\s*=\s*(.*?)$| )
        {
            my $probes_results_path = $1;

            not -d $probes_results_path and die( "The folder '$probes_results_path' does not exist\n" );

            $PROBES_RESULTS_PATH = $probes_results_path;
        }
        else
        {
            common::printLog( "The parameter '$line' is not known, it has been skipped\n" );
            next;
        }
    }

    not defined $TCP_PORT               and die( "You have to define the TCP port to listen on\n" );
    not defined $PROBES_RESULTS_PATH    and die( "You have to define the path on where the probes results are stored\n" );

    common::printLog( "Config file loaded\n" );
}
