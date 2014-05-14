package common;

use strict;
use warnings;

use IPC::Open3;
use IO::Select;



# Parameters (within a hash):
#   command     :   the command to run
#   arguments   :   a list of all the parameters to send to the command as arguments
#   stdin       :   a list of all the data to feed to the script via STDIN
#   timeout     :   the maximum duration of the command in seconds (the command will be killed if it lasts longer than the timeout)
sub execute
{
    my $params = shift;
