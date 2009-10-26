package SCC::BaseSCCCommand;

use strict;
use warnings; no warnings 'uninitialized';

use Verbose;
$kVerbose = $SCC::kVerbose;

sub options {
    my $self=shift;
    no strict 'refs';
    return ${"$self\::Options"};
    use strict 'refs';
    }

1;
