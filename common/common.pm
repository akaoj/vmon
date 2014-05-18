package common;

use strict;
use warnings;

use Symbol;
use POSIX;

use lib '/usr/lib/vmon';
use Result;


# Parameters (within a hash):
#   command     :   the command to run
#   arguments   :   OPTIONAL - a list of all the parameters to send to the command as arguments
#   stdin       :   OPTIONAL - a list of all the data to feed to the script via STDIN
#   timeout     :   OPTIONAL - the maximum duration of the command in seconds (the command will be killed if it lasts longer than the timeout), default to 5 seconds
sub execute
{
    my $params = shift;

    my $command     =   $params->{ 'command' };
    my @arguments   =   @{ $params->{ 'arguments' } }   ||  ( );
    my @stdin       =   @{ $params->{ 'stdin' } }       ||  ( );
    my $timeout     =   $params->{ 'timeout' }          ||  5;

    not $command and return Result->MISSING_PARAMETER( 'message' => 'You have to provide the command to run' );

    # We prepare the command
    my @commandsList = ( $command, @arguments );

    my @stdout = ( );
    my @stderr = ( );

    my $exitCode = -1;

    # We run the command but we control the timeout
    eval
    {
        local $SIG{ 'ALRM' } = sub{ die( "alarm_execute\n" ); };
        alarm $timeout;

        require IPC::Open3;
        require IO::Select;

        my( $in, $out, $err );
        $err = Symbol::gensym( );

        my $pid = IPC::Open3::open3( $in, $out, $err, @commandsList );

        # We feed the stdin
        foreach my $line( @stdin )
        {
            chomp( $line );
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
                    die( "The line read was neither from STDOUT nor STDERR, this is not normal\n" );
                }
            }
        }

        close( $out );
        close( $err );

        chomp( @stdout );
        chomp( @stderr );

        $exitCode = $? >> 8;

        alarm 0;
    };
    if( $@ )
    {
        $@ eq "alarm_execute\n" and return Result->TIMEOUT( 'message' => "The command '$command' timed out after $timeout seconds" );
        return Result->INTERNAL_ERROR( 'message' => "The command '$command' failed because of: $@" );
    }

    my $return = { 'stdout' => \@stdout, 'stderr' => \@stderr, 'exitCode' => $exitCode };

    if( $exitCode != 0 )
    {
        return Result->INTERNAL_ERROR( 'message' => "The command '$command' exited abnormally because of: " . join( "\n", @stderr ), 'value' => $return );
    }

    return Result->SUCCESS( 'message' => "The command '$command' executed successfully", 'value' => $return );
}



# Load the configuration
sub loadConfig
{

}


# Print a log starting with a date
sub printLog
{
    my $message = shift;

    not defined $message and return;

    chomp( $message );

    print strftime( "%Y-%m-%d %H:%M:%S $message\n", localtime( time ) );
}

1;
