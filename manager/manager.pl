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

my $pid = fork( );
not defined $pid and vmon::common::die( "Can't daemonize because of: $!" );

# We stop the father
if( $pid != 0 )
{
    vmon::common::print( "Process forked with pid $pid, ending..." );
    exit( 0 );
}

# Now we are forked, we close all STDIN/OUT
close( STDIN );
close( STDOUT );

# We keep STDERR open so we can stil die( ) and be noticed by the caller

# We open STDOUT to the logfile
not open( STDOUT, '>>', $VMON_LOG_FILE ) and vmon::common::die( "Can't open the logfile '$VMON_LOG_FILE' because of: $!" );

# We now can close STDERR and reopen it to the logfile
close( STDERR );
if( not open( STDERR, '>>', $VMON_LOG_FILE ) )
{
    vmon::common::print( "Can't redirect STDERR to logfile '$VMON_LOG_FILE' because of: $!" );
    exit( 1 );
}

vmon::common::print( 'Process forked, loading the probes configs...' );



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

        vmon::common::print( "Processing probe '$probe'..." );

        _processProbe( { 'probe' => $probe, 'config' => $probesConfiguration->{ $probe }, 'stats' => $probesStats->{ $probe } } );

        vmon::common::print( "Probe '$probe' processed" );
    }

    vmon::common::print( "All probes processed, sleeping for $VMON_RUN_LOOP_DELAY seconds..." );

    # Now all probes are being processed, we sleep
    sleep( $VMON_RUN_LOOP_DELAY );
}


#TODO: _processProbe