package vmon::common;

use strict;
use warnings;

use POSIX;



#################################################
#   Constants                                   #
#################################################

# Base folder
our $VMON_FOLDER = '/etc/vmon';

# Process names
our $VMON_SCHEDULER = 'vmon-scheduler';
our $VMON_RESPONDER = 'vmon-responder';

# Config file
our $CONFIG_FILE = "$VMON_FOLDER/vmon.conf";

# Default log directory and file
our $VMON_LOG_FOLDER     = '/var/log';
our $PROBES_LOG_FOLDER   = "$VMON_LOG_FOLDER/vmon";

# Default port
our $VMON_RESPONDER_PORT = 12080;

# Locks
our $LOCKS_FOLDER           = "$VMON_FOLDER/locks";
our $VMON_SCHEDULER_LOCK    = "$LOCKS_FOLDER/$VMON_SCHEDULER.lock";
our $VMON_RESPONDER_LOCK    = "$LOCKS_FOLDER/$VMON_RESPONDER.lock";
# Results folder
our $RESULTS_FOLDER         = "$VMON_FOLDER/results";
# Base probes folder
our $PROBES_FOLDER          = "$VMON_FOLDER/probes";
# Probes: scripts/binaries
our $PROBES_BIN_FOLDER      = "$PROBES_FOLDER/bin";
# Probes: configuration
our $PROBES_CONF_FOLDER     = "$PROBES_FOLDER/config";
# Probes: robots
our $PROBES_ROBOTS_FOLDER   = "$PROBES_FOLDER/robots";

# How long to wait before each loop on the probes (this will limit the lesser value of the delay for the probes) - set to 10 seconds
our $VMON_RUN_LOOP_DELAY = 1;



# Statuses:
our $STATUS_OK          = 0;
our $STATUS_INFO        = 1;
our $STATUS_WARNING     = 2;
our $STATUS_ALERT       = 3;
our $STATUS_CRITICAL    = 4;
our $STATUS_TIMEOUT     = 5;
our $STATUS_DIED        = 6;
our $STATUS_INVALID     = 7;
our $STATUS_OUTDATED    = 8;
our $STATUS_MISSING     = 9;
our $STATUS_UNKNOWN     = 10;

# This define the statuses that a probe can return
our @STATUSES_AVAILABLE_PROBES = ( $STATUS_OK, $STATUS_INFO, $STATUS_WARNING, $STATUS_ALERT, $STATUS_CRITICAL );
# This define all the statuses available
our @STATUSES_AVAILABLE = ( $STATUS_OK, $STATUS_INFO, $STATUS_WARNING, $STATUS_ALERT, $STATUS_CRITICAL, $STATUS_TIMEOUT, $STATUS_DIED, $STATUS_INVALID, $STATUS_OUTDATED, $STATUS_MISSING, $STATUS_UNKNOWN );





#################################################
#   Library                                     #
#################################################

# This will print a message to STDOUT (or STDERR if STDOUT is not open)
sub print
{
    my $message = shift;

    # If the message is empty, we return (can't simply check with 'not' because the message may contain a simple '0')
    not defined $message and return;
    $message eq '' and return;

    my $date = _getDate( );

    if( tell( STDOUT ) != -1 )
    {
        CORE::print STDOUT "$date - $message\n";
    }
    elsif( tell( STDERR ) != -1 )
    {
        CORE::print STDERR "$date - FALLBACK FROM STDOUT - $message\n";
    }
    else
    {
        vmon::common::die( "Can't write neither on STDOUT nor on STDERR" );
    }

}

# This will die with a formatted message
sub die
{
    my $message = shift;
    my $date    = _getDate( );

    CORE::die( "$date [error] $message\n" );
}

sub _getDate
{
    return POSIX::strftime( '%Y-%m-%d %H:%M:%S', localtime( time ) );
}



# This will return the list of all probes available (the starting point is the config file; which means a probe will exists if its config file exists)
# Returns:
#   a reference of an array containing all the probes found
sub getAllAvailableProbes
{
    not opendir( PROBES_CONFIG_FOLDER, $PROBES_CONF_FOLDER ) and vmon::common::die( "Can't open the probes config folder '$PROBES_CONF_FOLDER' because of: $!" );
    my @configFiles = readdir( PROBES_CONFIG_FOLDER );
    close( PROBES_CONFIG_FOLDER );

    chomp( @configFiles );

    my @probesFound = ( );

    foreach my $probe( @configFiles )
    {
        $probe eq '.'  and next;
        $probe eq '..' and next;

        $probe !~ m|^(.*?)\.conf$| and next;

        # If the file is a valid config file, we add the probe to the list
        push( @probesFound, $1 );
    }

    return \@probesFound;
}



# This will daemonize the process: it will be forked, the child filehandles will be redirected to the given logs and a lockfile will be created
# Note that if the lockfile already exists and the process is still running, this sub will return undef
# Parameters (within a hash):
#   name    :   the daemon name (to set the lockfile and logs names)
# Returns:
#   undef if an error occured, 0 if we are the child, not 0 if we are the father
sub daemonize
{
    my $params = shift;

    my $name = $params->{ 'name' };

    if( not $name )
    {
        vmon::common::print( 'You have to provide the name of the daemon for the daemonize operation' );
        return undef;
    }

    # This will hold the path to the log file
    my $logFile = '';

    # If the process is the scheduler or the responder, we set the logfiles in the root of the log directory, else we put them in the vmon folder in the log directory
    if( grep{ $name eq $_ } ( $VMON_SCHEDULER, $VMON_RESPONDER ) )
    {
        $logFile = "$VMON_LOG_FOLDER/$name.log";
    }
    else
    {
        $logFile = "$PROBES_LOG_FOLDER/$name.log";
    }

    my $pid = fork( );
    if( not defined $pid )
    {
        vmon::common::print( "Can't fork because of: $!" );
        return undef;
    }

    # If we are the father, we return the child process ID
    if( $pid != 0 )
    {
        vmon::common::print( "Process forked with pid $pid" );
        return $pid;
    }

    # If we are the child, we redirect all OUT filehandles

    # We keep STDERR open so we can still print something if needed
    close( STDOUT );

    # We open STDOUT to the logfile
    if( not open( STDOUT, '>>', $logFile ) )
    {
        vmon::common::print( "Can't redirect STDOUT to the logfile '$logFile' because of: $!" );
        exit( 1 );
    }

    # We now can close STDERR and reopen it to the logfile
    close( STDERR );
    if( not open( STDERR, '>>', $logFile ) )
    {
        vmon::common::print( "Can't redirect STDERR to the logfile '$logFile' because of: $!" );
        exit( 2 );
    }

    vmon::common::print( 'Process forked' );
    return 0;
}



# This will open the config file for the given probe, load the configuration and send back a hash with all keys => values
# Parameters (within a hash):
#   probe   :   the name of the probe
# Returns:
#   a hash reference containing all keys => values found
sub loadConfigFile
{
    my $params = shift;

    my $probe = "$PROBES_CONF_FOLDER/$params->{ 'probe' }.conf";

    not -f $probe and vmon::common::die( "The config file '$probe' does not exist" );

    not open( CONFIG_FILE, '<', $probe ) and vmon::common::die( "Can't read the config file '$probe' because of: $!" );
    my @fileContent = <CONFIG_FILE>;
    close( CONFIG_FILE );

    chomp( @fileContent );

    my $config = { };

    foreach my $line( @fileContent )
    {
        # We skip comments and empty lines
        $line =~ m|^\s*$|   and next;
        $line =~ m|^#|      and next;

        $line !~ m|^\s*([a-zA-Z0-9._-]+)\s*=\s*(.*?)\s*$| and next;

        # We retrieve the key and the value for the current parameter
        my $key     = $1;
        my $value   = $2;

        not defined $key    and next;
        not defined $value  and next;

        # We finally add the couple to the hash
        $config->{ $key } = $value;

        vmon::common::print( "$key => $value" );
    }

    return $config;
}



# This sub will execute the given Linux command with the given parameters
# Parameters (within a hash):
#   command   :   the command to run
#   arguments :   OPTIONAL - a list of all the parameters to send to the command as arguments
#   stdin     :   OPTIONAL - a list of all the data to feed to the script via STDIN
#   timeout   :   OPTIONAL - the maximum duration of the command in seconds (the command will be killed if it lasts longer than the timeout), default to 5 seconds
# Returns:
#   a hash containing a status, a message, the STDOUT, the STDERR and the exit code of the command
#   i.e.: { 'status' => 'ok', 'message' => 'Command executed successfully', 'stdout' => ARRAY, 'stderr' => ARRAY, 'exitCode' => 0 }
sub execute
{
    my $params = shift;

    my $command     = $params->{ 'command' };
    my @arguments   = @{ $params->{ 'arguments' }   || [ ] };
    my @stdin       = @{ $params->{ 'stdin' }       || [ ] };
    my $timeout     = $params->{ 'timeout' }        || 5;

    not $command and vmon::common::die( 'You have to provide the command to run' );

    chomp( @arguments );

    # We prepare the command
    my @commandsList = ( $command, @arguments );

    my @stdout = ( );
    my @stderr = ( );

    not -x $command and return { 'status' => 'error', 'message' => "The command '$command' is not executable, can't run it", 'stdout' => \@stdout, 'stderr' => \@stderr };

    my $exitCode = -1;

    # We run the command but we control the timeout
    eval
    {
        local $SIG{ 'ALRM' } = sub { CORE::die( "alarm\n" ); };
        alarm $timeout;

        require IPC::Open3;
        require IO::Select;
        require Symbol;

        my( $in, $out, $err );
        $err = Symbol::gensym( );

        my $pid = IPC::Open3::open3( $in, $out, $err, @commandsList );

        # We feed the stdin (only if we can)
        if( -t $in )
        {
            foreach my $line( @stdin )
            {
                print $in $line;
            }
        }

        close( $in );

        # We now retrieve both STDOUT and STDERR
        my $select = new IO::Select;

        $select->add( $out, $err );

        while( my @filehandles = $select->can_read( ) )
        {
            foreach my $filehandle( @filehandles )
            {
                my $line = <$filehandle>;

                if( not defined $line )
                {
                    $select->remove( $filehandle );
                    next;
                }

                chomp( $line );

                if( $filehandle == $out )
                {
                    push( @stdout, $line );
                }
                elsif( $filehandle == $err )
                {
                    push( @stderr, $line );
                }
                else
                {
                    CORE::die( "The line read was neither from STDOUT nor STDERR, this is not normal, its content is: $line" );
                }
            }
        }

        close( $out );
        close( $err );

        waitpid( $pid, 0 );

        $exitCode = $? >> 8;

        alarm 0;
    };
    if( $@ )
    {
        # Timeout
        $@ eq "alarm\n" and return { 'status' => 'timeout', 'message' => "The command '$command' timed out after $timeout seconds", 'stdout' => \@stdout, 'stderr' => \@stderr };

        # Other problem
        return { 'status' => 'died', 'message' => "The Perl wrapper around the command '$command' died because of: $@", 'stdout' => \@stdout, 'stderr' => \@stderr };
    }

    if( $exitCode != 0 )
    {
        return { 'status' => 'died', 'message' => "The command '$command' died and returned the exit code: $exitCode", 'stdout' => \@stdout, 'stderr' => \@stderr, 'exitCode' => $exitCode };
    }

    return { 'status' => 'ok', 'message' => "The command '$command' executed successfully", 'stdout' => \@stdout, 'stderr' => \@stderr, 'exitCode' => $exitCode };
}

1;
