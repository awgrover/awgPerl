package SCC::Commands::list_commands;
use base qw(SCC::BaseCommand);

use strict;
use warnings; no warnings 'uninitialized';
use Module::Find;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub usage {
    my $self=shift;
    my ($command) = @_;
    return $command.' <args>  # list commands';
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        "list" => "just list commands, no path/desc",
        );
    }

sub doCommand {
    my $self=shift;
    $self->SUPER::doCommand(@_);

    vverbose 4,"after getoptions";

    my %modules = map { ($_,undef) } findallmod('SCC::Commands');
    my @modules = sort keys (%modules);
    $awgrover::Getopt::gExitOnHelp = 0;
    foreach (@modules) {
        if ($self->options->{'list'}) {
            /([^:]+)$/;
            print "$1\n";
            }
        else {
            eval "use $_"; die $@ if $@;
            @ARGV = "-usage";
            $_->getOptions();
            }
        }
    }

sub delegate {}
1;
