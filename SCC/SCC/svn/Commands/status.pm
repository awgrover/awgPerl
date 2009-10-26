package SCC::SCC::svn::Commands::status;
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
    system("cd $projectBase; svn status -u");
    }

1;
