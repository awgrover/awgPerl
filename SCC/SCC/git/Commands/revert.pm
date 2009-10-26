package SCC::SCC::git::Commands::revert;
use base qw(SCC::BaseSCCCommand SCC::Util);

use SCC::SCC::git::Utils;

use strict;
use warnings; no warnings 'uninitialized';

use SH;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;


    #my @alreadyModified = map {chomp; $_} `git status | egrep '^#\tmodified:'`;
    #foreach my $rawfile (@ARGV) {
    #     unlink $rawfile if grep { /\s$rawfile$/ } @alreadyModified;
    #    }

    my @files = map { SH::quote($_) } @ARGV;
    system("git checkout ".join(" ",@files));
    }

1;
