package SCC::Commands::which;
use base qw(SCC::BaseCommand);

use strict;
use warnings; no warnings 'uninitialized';

use Verbose;
$kVerbose = $SCC::kVerbose;

sub usage {
    my $self=shift;
    my ($command) = @_;
    return $command.' <options> # tells which scc'
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        "where|w" => "more verbose about finding the scc",
        map {($_ => "commit $_") } (sort keys %{$self->knownSCC}), # each scc
        );
    }

sub delegate {
    }

sub doCommand {
    my $self=shift;
    $self->SUPER::doCommand(@_);

    vverbose 4,"after getoptions";

    my $scc = $self->findPrimarySCC();
    print "$scc\n";
    }

1;
