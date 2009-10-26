package SCC::SCC::git::Commands::inventory;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;
    my $filter;
    if ($self->options->{'dir'}) {
        $filter="-d";
        }
    elsif ($self->options->{'file'}) {
        # the default is file only!
        $filter="";
        }
    else {
        $filter="-t";
        }
    # my $cmd = "git ls-tree -r --name-only $filter refs/heads/`git branch | egrep '^\*' | awk '{print \$2}'`";
    my $cmd = "git ls-tree -r --name-only $filter HEAD";
    system($cmd);
    }

1;
