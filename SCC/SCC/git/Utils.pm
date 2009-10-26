package SCC::SCC::git::Utils;
use warnings; use strict; no warnings 'uninitialized';

sub branch {
    my $branch = (`git branch | egrep '^\*' | sed 's/^..//'`)[0];
    chomp $branch;
    return $branch;
    }
1;
