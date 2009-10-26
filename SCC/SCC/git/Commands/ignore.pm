package SCC::SCC::git::Commands::ignore;
use base qw(SCC::BaseSCCIgnore);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use IO::File;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub ignoreFile {
    my $self=shift;
    return ".gitignore";
    }

sub addIgnore {
    my $self=shift;
    my $f = $self->ignoreFile;
    print `git add $f >/dev/null`;
    }

sub hasIgnore {
    my $self=shift;
    return system("git ls-files --error-unmatch ".$self->ignoreFile." 1>/dev/null 2>&1") == 0;
    }

sub patternHelp {
        my $help = 
            "shell globs (* does not match /); ! is 'include'; /... head match";
        # and escape it
        $help =~ s/([\/\\])/\\$1/g;
        return $help;
        }

1;
