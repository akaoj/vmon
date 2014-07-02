#/!usr/bin/perl

use strict;
use warnings;

use IO::Socket;

use lib 'common';
use common;

# Autoflush the output
$| = 1;



#################################################
#   Constants                                   #
#################################################

# Base folder
my $VMON_FOLDER = '/etc/vmon';

# Config file
my $CONFIG_FILE = "$VMON_FOLDER/vmon.conf";

# Default log directory and file
my $VMON_LOG_FOLDER     = '/var/log';
my $PROBES_LOG_FOLDER   = "$VMON_LOG_FOLDER/vmon";
my $VMON_LOG_FILE       = "$VMON_LOG_FOLDER/vmon-manager.log";

# Default port
my $PORT = 12080;

# Probes folder
my $PROBES_FOLDER   = "$VMON_FOLDER/probes";
# Conf folder
my $CONF_FOLDER     = "$VMON_FOLDER/conf";
# Robots folder
my $ROBOTS_FOLDER   = "$VMON_FOLDER/robots";
# Results folder
my $RESULTS_FOLDER  = "$VMON_FOLDER/results";

# How long to wait before each loop on the probes (this will limit the lesser value of the delay for the probes) - set to 10 seconds
my $VMON_RUN_LOOP_DELAY = 10;



#################################################
#   Program                                     #
#################################################



# We first daemonize this script
vmon::common::print( 'Daemonizing the manager...' );

my $pid = vmon::common::forkAndRedirectFilehandles( { 'stdout' => $VMON_LOG_FILE } );

not defined $pid and vmon::common::die( "Can't daemonize, see logs at '$VMON_LOG_FILE' for more informations" );

# We stop the father
if( $pid != 0 )
{
    vmon::common::print( "Child forked with pid '$pid', ending father..." );
    exit( 0 );
}

vmon::common::print( 'We are the child, loading the probes configs...' );



# Now STDOUT and STDERR are opened to the logfile, we can start working

# We first load all config files for all the probes
not opendir( PROBES_CONFIG_FOLDER, $CONF_FOLDER ) and vmon::common::die( "Can't open the probes config folder '$CONF_FOLDER' because of: $!" );
my @configFiles = readdir( PROBES_CONFIG_FOLDER );
close( PROBES_CONFIG_FOLDER );

chomp( @configFiles );

if( scalar( @configFiles ) <= 2 )
{
    vmon::common::die( 'No probes found, aborting' );
}

# This hash will hold all the config for each probe
my $probesConfiguration = { };

foreach my $file( @configFiles )
{
    $file eq '.'  and next;
    $file eq '..' and next;

    $file !~ m|^(.*?)\.conf$| and next;

    my $probeName = $1;

    vmon::common::print( "Probe '$probeName' found, loading config..." );

    my $confHash = vmon::common::loadConfigFile( { 'file' => "$CONF_FOLDER/$file" } );

    # We check that the minimal parameters are set
    if( not $confHash->{ 'timeout' } or ( $confHash->{ 'timeout' } !~ m|^[0-9]+$| ) )
    {
        vmon::common::print( "The probe '$probeName' config does not supply the timeout parameter, skipping it..." );
        next;
    }
    elsif( not $confHash->{ 'delay' } or ( $confHash->{ 'delay' } !~ m|^[0-9]+$| ) )
    {
        vmon::common::print( "The probe '$probeName' config does not supply the delay parameter, skipping it..." );
        next;
    }

    $probesConfiguration->{ $probeName } = $confHash;
}

vmon::common::print( 'Configuration loaded for ' . scalar( keys( %{ $probesConfiguration } ) ) . ' probes; starting probes...' );



# Now the configuration is loaded and we are daemonized, we can start running all the probes

# This hash will hold all the information about the probes (last run, ...)
my $probesStats = { };

while( 1 )
{
    foreach my $probe( keys( %{ $probesConfiguration } ) )
    {
        # We initialize the stats if needed
        if( not exists $probesStats->{ $probe } )
        {
            vmon::common::print( "Initializing stats for probe '$probe'..." );
            $probesStats->{ $probe } = { 'lastRun' => 0 };
        }

        _processProbe( { 'probe' => $probe, 'config' => $probesConfiguration->{ $probe }, 'stats' => $probesStats->{ $probe } } );
    }

    vmon::common::print( "All probes processed, sleeping for $VMON_RUN_LOOP_DELAY seconds..." );

    # Now all probes are being processed, we sleep
    sleep( $VMON_RUN_LOOP_DELAY );
}



# This sub will process each probe in a different process so all probes can be run in parallel
# Parameters (within a hash):
#   probe   :   the name of the probe
#   config  :   the config of the probe
#   stats   :   the statistics of the probe
sub _processProbe
{
    my $params = shift;

    my $probe   = $params->{ 'probe' };
    # We make a deep copy of the config because we will remove elements later on
    my $config  = $params->{ 'config' };
    my $stats   = $params->{ 'stats' };

    vmon::common::print( "Processing probe '$probe'..." );

    if( not $probe or not $config or not $stats )
    {
        vmon::common::die( 'Missing the probe name, the config or the stats for processing the probe' );
    }

    # We first check that we actually need to run this probe
    my $probeDelay = $config->{ 'delay' };

    my $currentTime = time;

    # If the delay is still not elapsed, we do not process this probe
    if( ( $currentTime - $stats->{ 'lastRun' } ) < $probeDelay )
    {
        vmon::common::print( "The delay for the probe '$probe' is not yet elapsed, skipping this probe..." );
        return;
    }

    # This probe is ready to be run, we fork to run it
    my $pid = vmon::common::forkAndRedirectFilehandles( { 'stdout' => "$PROBES_LOG_FOLDER/$probe.log" } );

    if( not defined $pid )
    {
        vmon::common::print( "Can't fork for processing probe '$probe', see vmon logs for details" );
        return;
    }
    elsif( $pid != 0 )
    {
        # If we are the father, we have nothing else to do, we can return to process the next probe
        vmon::common::print( "Probe '$probe' forked and being processed, processing the next one..." );
        return;
    }

    # We are the child and we have to process the probe

    # We build the data we will send in probe's STDIN
    my @probeStdin = ( );

    foreach my $configKey( keys( %{ $config } ) )
    {
        push( @probeStdin, "$configKey=$config->{ $configKey }" );
    }

    vmon::common::print( "Running probe '$PROBES_FOLDER/$probe'..." );

    my $result = vmon::common::execute( { 'command' => "$PROBES_FOLDER/$probe", 'stdin' => \@probeStdin, 'timeout' => $config->{ 'timeout' } } );

    my $status = $result->{ 'status' };
    my $message = $result->{ 'message' };

    # TODO: if timeout => oco 5 ; if died => oco 5?
    # and remove this peut-être : $status ne 'ok' and vmon::common::die( $message );








    vmon::common::print( "Probe '$probe' processed" );

    return;
}

