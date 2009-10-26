package SCC::SCC::tla::Commands::inventory;
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
        $filter=" -d";
        }
    elsif ($self->options->{'file'}) {
        $filter=" -f";
        }
    system('tla inventory -s'.$filter);
    }

1;
