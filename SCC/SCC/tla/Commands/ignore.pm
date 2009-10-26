package SCC::SCC::tla::Commands::ignore;
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
    return ".arch-inventory";
    }

sub addIgnore {
    my $self=shift;
    my $f = $self->ignoreFile;
    print `tla add $f >/dev/null`;
    }

sub hasIgnore {
    my $self=shift;
    return system("tla id ".$self->ignoreFile." 1>/dev/null 2>&1") == 0;
    }

sub patternHelp {
        my $help = 
            "egrep patterns (pin with ^ and \$)";
        # and escape it
        $help =~ s/([\/\\\$])/\\$1/g;
        return $help;
        }

1;
