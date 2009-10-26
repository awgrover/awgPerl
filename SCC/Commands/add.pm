package SCC::Commands::add;
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
    return $command.' <options> <files...>  # adds files';
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        'where|w' => 'tell which/where default scc for this dir',
        map {($_ => "commit $_") } (sort keys %{$self->knownSCC}), # each scc
        );
    }

1;
