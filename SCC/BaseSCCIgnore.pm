package SCC::BaseSCCIgnore;
use base qw(SCC::BaseSCCCommand);
# base for the SCC::$scc::Command::ignore

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use IO::File;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    if (scalar @ARGV) {
        $self->ignoreFiles();
        }
    else {
        $self->editIgnorePatterns();
        }
    }

sub ignoreFiles {
    my $self=shift;
    my $wasDir = cwd();
    foreach my $filePattern (@ARGV) {
        chdir dirname($filePattern);
        my $already = $self->hasIgnore;
        my $fh = IO::File->new(">>".$self->ignoreFile)
            || die "Can't write to ".$self->ignoreFile.": $!";
        print $fh $filePattern,"\n";
        verbose "ignore ".cwd()."/".$self->ignoreFile.": $filePattern";
        close $fh;
        $self->addIgnore if !$already;
        chdir $wasDir;
        }
    }

sub editIgnorePatterns {
    my $self=shift;

    my $already = $self->hasIgnore;

    my $help = $self->patternHelp;
    system("vi -c '0 s/^/# patterns: $help\\r/' ".$self->ignoreFile);

    if (-f $self->ignoreFile) {
        system("sed -i '/^# patterns: / d' ".$self->ignoreFile);

        $self->addIgnore if !$already;
        }
    }

# override below
sub ignoreFile {
    my $self=shift;
    die "return the ignore file name";
    }

sub addIgnore {
    my $self=shift;
    my $f = $self->ignoreFile;
    die "execute the 'scc add $f' command";
    }

sub hasIgnore {
    my $self=shift;
    die "return #t/#f for ignoreFile already added to scc";
    }

sub patternHelp {
        my $help = 
            "some brief clue as to the pattern language";
        # and escape it
        $help =~ s/([\/\\])/\\$1/g;
        die "return $help";
        }

1;
