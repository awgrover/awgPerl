package SCC::SCC::svn::Commands::ignore;
use base qw(SCC::BaseSCCIgnore);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use IO::File;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub editIgnorePatterns {
    # sadly, can't introduce patternHelp here
    system('svn propedit svn:ignore .')
    }

sub patternHelp {
        my $help = 
            "shell globs";
        # and escape it
        $help =~ s/([\/\\])/\\$1/g;
        return $help;
        }

1;
