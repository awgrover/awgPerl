package SCC::SCC::git::Commands::status;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    my ($projectBase) = `scc which -w | awk '{print \$3}'`;
    chomp $projectBase;
    my $missingPatches = "cd $projectBase;".q{ branchref=`awk '{print $2}' .git/HEAD` ; git log $option `basename $branchref`..remotes/origin/`basename $branchref` | cat };
    system('echo "remote archive"; '.$missingPatches.'; echo "working dir"; git status');
    }

1;
