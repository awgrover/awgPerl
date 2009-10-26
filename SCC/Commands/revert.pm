package SCC::Commands::revert;
use base qw(SCC::BaseCommand);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub usage {
    my $self=shift;
    my ($command) = @_;
    return $command.' <options> <files...>  # reverts files to last commit';
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        );
    }

1;
