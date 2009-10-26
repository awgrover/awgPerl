package SCC::Commands::inventory;
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
    return "$command <options>  # lists the files/dirs in ./ under scc control"
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        "dir" => "Only list dirs",
        "file" => "Only list files",
        map {($_ => "commit $_") } (sort keys %{$self->knownSCC}), # each scc #FIXME: make an option to "scc"
        );
    }

1;
