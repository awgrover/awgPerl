package SCC::SCC::svn::Commands::add;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use SH;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    my @files = map { SH::quote($_) } @ARGV;
    system("svn add ".join(" ",@files));
    }

1;
