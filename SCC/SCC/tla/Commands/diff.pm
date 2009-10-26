package SCC::SCC::tla::Commands::diff;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    system(
        'tla changes --diffs '
        .join(" ",map {$self->shEscape($_) } @ARGV)
        ." | awk '".'/^\* modified files/, 0 {print $0;next} /\/\.arch-ids/ {next} {print $0}'."' | less -p '^--- ' "
        );
    }

1;
