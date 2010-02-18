package SCC::Commands::commit;
use base qw(SCC::BaseCommand);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use SH;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub usage {
    my $self=shift;
    my ($command) = @_;
    return $command.' <options> "message"  [files] # commits changes with message'
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        'where|w' => 'tell which/where default scc for this dir',
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
    my $msg = shift @ARGV;
    my @files = map {SH::quote($_)} @ARGV;
    my $command = (@files && $self->knownSCC->{$scc}->{'command_with_files'}) 
        || $self->knownSCC->{$scc}->{'command'};
    system($command." ".SH::quote($msg)." ".join(" ",@files));
    }

1;
