package vmon::common;

use strict;
use warnings;

use POSIX;


# This will print a message
sub print
{
    my $message = shift;
    my $date    = _getDate( );

    print STDOUT "$date $message\n";
}

# This will print an error message and die
sub die
{
    my $message = shift;
    my $date    = _getDate( );

    CORE::die( "$date [error] $message\n" );
}

sub _getDate
{
    return POSIX::strftime( '%Y-%m-%d %H:%M:%S -', localtime( time ) );
}

# This will check if a given config line match the specified parameter
# Parameters (within a hash):
#   configLine  :   the line to analyze
#   parameter   :   the parameter to match
# Returns:
#   the value found (if it matches), undefined else
sub matchConfigParameter
{
    my $params = shift;

    not $params->{ 'configLine' } and return undef;
    not $params->{ 'parameter' }  and return undef;

    if( $params->{ 'configLine' } =~ m|^\s*$params->{ 'parameter' }\s*=\s*(.*?)\s*$| )
    {
        return $1;
    }

    return undef;
}

# This will open the given config file, load the configuration and send back a hash with all keys => values
# Parameters (within a hash):
#   file    :   the file to load
# Returns:
#   a hash reference containing all keys => values found
sub loadConfigFile
{
    my $params = shift;

    my $file = $params->{ 'file' };

    not -f $file and vmon::common::die( "The config file '$file' does not exist" );

    not open( FILE, '<', $file ) and vmon::common::die( "Can't read the config file '$file' because of: $!" );
    my @fileContent = <FILE>;
    close( FILE );

    chomp( @fileContent );

    my $config = { };

    foreach my $line( @fileContent )
    {
        # We skip comments and empty lines
        $line =~ m|^\s*$|   and next;
        $line =~ m|^#|      and next;

        $line !~ m|^\s*([a-zA-Z0-9._-])+\s*=\s*(.*?)\s*$| and next;

        # We retrieve the key and the value for the current parameter
        my $key     = $1;
        my $value   = $2;

        not defined $key    and next;
        not defined $value  and next;

        # We finally add the couple to the hash
        $config->{ $key } = $value;
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

    not $command and return { 'status' => 'missing_parameter', 'message' => 'You have to provide the command to run' };

    chomp( @arguments );
    chomp( @stdin );

    # We prepare the command
    my @commandsList = ( $command, @arguments );

    my @stdout = ( );
    my @stderr = ( );

    my $exitCode = -1;

    # We run the command but we control the timeout
    eval
    {
        local $SIG{ 'ALRM' } = sub{ CORE::die( "alarm_execute\n" ); };
        alarm $timeout;

        require IPC::Open3;
        require IO::Select;

        my( $in, $out, $err );
        $err = Symbol::gensym( );

        my $pid = IPC::Open3::open3( $in, $out, $err, @commandsList );

        # We feed the stdin
        foreach my $line( @stdin )
        {
            print $in "$line\n";
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

        $exitCode = $? >> 8;

        alarm 0;
    };
    if( $@ )
    {
        # Timeout
        $@ eq "alarm_execute\n" and return { 'status' => 'timeout', 'message' => "The command '$command' timed out after $timeout seconds" };

        # Other problem
        return { 'status' => 'internal_error', 'message' => "The command '$command' failed because of: $@" };
    }

    return { 'status' => 'ok', 'message' => 'The command executed successfully', 'stdout' => \@stdout, 'stderr' => \@stderr, 'exitCode' => $exitCode };
}

1;
