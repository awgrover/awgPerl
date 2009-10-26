#!/bin/sh
perl -x "$0" "$@"
exit
#!perl

package awg::outline;
use strict; use warnings; no warnings 'uninitialized';

# grep'able outlines
# --- [-v] pattern files (or <)

my $exclude = 0;
if ($ARGV[0] eq '-v') {
    $exclude = 1;
    shift @ARGV;
    }
my $pattern = qr/$ARGV[0]/;
shift @ARGV;

sub main {
    my @parent;

    while (<>) {
        $_ =~ /^\s*/;
        my $level = length $&;
        $parent[$level] = $_;
        if ($exclude ? ($_ !~ $pattern) : ($_ =~ $pattern)) {
            foreach my $parent_level (0..$level-1) {
                print $parent[$parent_level] if defined $parent[$parent_level];
                $parent[$parent_level] = undef
                }
            print $_;
            $parent[$level] = undef;
            }
        }
    }

main();
