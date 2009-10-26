package SCC::SCC::tla::Commands::status;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    system('tla changes | grep -v /.arch-ids; tla tree-lint && tla missing');
    }

1;
