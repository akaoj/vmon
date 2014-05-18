package Result;

use strict;
no strict 'refs';
use warnings;

use JSON;

BEGIN
{
    my %types =
    (
        'OK'                =>  { 'status' => 100, 'aliases' => [ qw{ SUCCESS } ] },
        'NOTHING_CHANGED'   =>  { 'status' => 101, 'aliases' => [ qw{ NOTHING_TO_DO } ] },
        'INTERNAL_ERROR'    =>  { 'status' => 200, 'aliases' => [ qw{ SERVER_ERROR } ] },
        'FORBIDDEN'         =>  { 'status' => 300, 'aliases' => [ qw{ NOT_ALLOWED } ] },
        'INVALID_PARAMETER' =>  { 'status' => 400, 'aliases' => [ qw{ INVALID_PARAMETERS INVALID_ARGUMENT INVALID_ARGUMENTS } ] },
        'MISSING_PARAMETER' =>  { 'status' => 401, 'aliases' => [ qw{ MISSING _PARAMETERS MISSING_ARGUMENT MISSING_ARGUMENTS } ] },
        'TIMEOUT'           =>  { 'status' => 500, 'aliases' => [ ] },
        'UNKNOWN_ERROR'     =>  { 'status' => 999, 'aliases' => [ qw{ UNKNOWN } ] },
    );

    foreach my $type( keys( %types ) )
    {
        *$type = sub
        {
            my( $this, %params ) = @_;

            if( not $this )
            {
                return $types{ $type }->{ 'status' };
            }

            return Result->new( 'status' => $types{ $type }->{ 'status' }, %params );
        };

        foreach my $alias( @{ $types{ $type }->{ 'aliases' } } )
        {
            *$alias = sub
            {
                my( $this, %params ) = @_;

                if( not $this )
                {
                    return $types{ $type }->{ 'status' };
                }

                return Result->new( 'status' => $types{ $type }->{ 'status' }, %params );
            };
        }
    }
}



use overload
    'bool'  =>  sub
    {
        my $this = shift;

        if( $this->status( ) >= 200 )
        {
            return 0;
        }
        else
        {
            return 1;
        }
    };



sub new
{
    my( $class, %params ) = @_;

    my $this = { };

    bless( $this, $class );

    $this->{ 'status' }     =   $params{ 'status' }     || 999;
    $this->{ 'message' }    =   $params{ 'message' }    || '';
    $this->{ 'value' }      =   $params{ 'value' };

    return $this;
}

sub status
{
    my $this = shift;

    return $this->{ 'status' };
}

sub message
{
    my $this = shift;

    return $this->{ 'message' };
}

sub value
{
    my $this = shift;

    return $this->{ 'value' };
}

sub TO_JSON
{
    my $this = shift;
    return { %{ $this } };
}

sub toJson
{
    my $this = shift;

    my $json = JSON->new->utf8->convert_blessed( 1 );

    return $json->encode( $this );
}

sub fromJson
{
    my $string = shift;

    my $json = JSON->new->utf8->convert_blessed( 1 );

    my $hash = $json->decode( $string );

    return Result->new( 'status' => $hash->{ 'status' }, 'message' => $hash->{ 'message' }, 'value' => $hash->{ 'value' } );
}

1;
