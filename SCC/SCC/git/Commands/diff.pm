package SCC::SCC::git::Commands::diff;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    # exactly like this for "working tree vs. commit" (as opposed to "index vs. commmit")
    system("git diff HEAD | less -p '^--- '");
    }

1;
