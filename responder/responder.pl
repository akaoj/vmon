#/!usr/bin/perl

use strict;
use warnings;

use IO::Socket;

use lib 'common';
use vmon::common;

# Autoflush the output
$| = 1;



#################################################
#   Constants                                   #
#################################################

# Config file
my $CONFIG_FILE = '/etc/vmon/vmon.conf';

# Default log directory and file
my $LOG_FOLDER  = '/var/log/vmon';
my $LOG_FILE    = 'vmon-responder.log';

# Default port
my $PORT = 12080;

# Probes folder
my $PROBES_FOLDER = '/etc/vmon/probes';



#################################################
#   Program                                     #
#################################################

# We first load the config
not -f $CONFIG_FILE and vmon::common::die( "The config file '$CONFIG_FILE' does not exist" );

not open( CONFIG, '<', $CONFIG_FILE ) and vmon::common::die( "Can't open the config file because of: $!" );
my @config = <CONFIG>;
close( CONFIG );

chomp( @config );

foreach my $line( @config )
{
    if( $line =~ m|^\s*port\s*=\s*(.*?)\s*$| )
    {
        $PORT = $1;
    }
    elsif( $line =~ m|^\s*log_folder\s*=\s*(.*?)\s*$| )
    {
        $LOG_FOLDER = $1;
        $LOG_FOLDER =~ s|/+$||g;
    }
    elsif( $line =~ m|^\s*probes_folder\s*=\s*(.*?)\s*$| )
    {
        $PROBES_FOLDER = $1;
    }
}

$LOG_FILE = "$LOG_FOLDER/$LOG_FILE";



# We can now daemonize this script
vmon::common::print( 'Daemonizing the responder...' );

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

# We keep STDERR open so we can stil die( ) and be noticed by cron

# We open STDOUT to the logfile
not open( STDOUT, '>>', $LOG_FILE ) and vmon::common::die( "Can't open the logfile '$LOG_FILE' because of: $!" );

# We now can close STDERR and reopen it to the logfile
close( STDERR );
if( not open( STDERR, '>>', $LOG_FILE ) )
{
    vmon::common::print( "Can't redirect STDERR to logfile '$LOG_FILE' because of: $!" );
    exit( 1 );
}

# Now STDOUT and STDERR are opened to the logfile, we can start working
my $probesConfig = "$PROBES_FOLDER/config";

not opendir( PROBES_CONFIG_FOLDER, $probesConfig ) and vmon::common::die( "Can't open the probes config folder '$probesConfig' because of: $!" );
my @configFiles = readdir( PROBES_CONFIG_FOLDER );
close( PROBES_CONFIG_FOLDER );

chomp( @configFiles );

# This hash will hold all the config for each probe
my $probesConfiguration = { };

foreach my $file( @configFiles )
{
    $file eq '.' and next;
    $file eq '..' and next;

    $file !~ m|^(.*?)\.conf$| and next;

    my $probeName = $1;

    vmon::common::print( "Probe '$probeName' found, loading config..." );

    if( not open( CONFIG_FILE, '<', "$probesConfig/$file" ) )
    {
        vmon::common::print( "Config file for probe '$probeName' can't be processed because of: $!" );
        next;
    }
    my @probeConfig = <CONFIG_FILE>;
    close( CONFIG_FILE );

    chomp( @probeConfig );

    foreach my $configLine( @probesConfig )
    {
        my $value = vmon::common::matchConfigParameter( 'configLine' => $configLine, 'parameter'
