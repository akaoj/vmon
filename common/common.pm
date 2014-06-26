package vmon::common;

use strict;
use warnings;



# This will print a message
sub print
{
    my $message = shift;

    print STDOUT "$message\n";
}

# This will print an error message and die
sub die
{
    my $message = shift;

    die( "$message\n" );
}

# This will check if a given config line match the specified parameter
# Parameters:
#   configLine  :   the line to analyze
#   parameter   :   the parameter to match
# Returns:
#   the value found (if it matches), undefined else
sub matchConfigParameter
{
    my %params = @_;

    not $params{ 'configLine' } and return undef;
    not $params{ 'parameter' }  and return undef;

    if( $params{ 'configLine' } =~ m|^\s*$params{ 'parameter' }\s*=\s*(.*?)\s*$| )
    {
        return $1;
    }

    return undef;
}

# TODO: un truc genre associateParams( 'fileContent' => \@fileContent, 'params' => qw{ port logDir ... } )
