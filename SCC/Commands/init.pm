package SCC::Commands::init;
use base qw(SCC::BaseCommand);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use Module::Find;
use Term::Menu;

use Verbose;
$kVerbose = $SCC::kVerbose;

our $MainBranch = 'main';

sub usage {
    my $self=shift;
    my ($command) = @_;
    return $command.' <options> <scc-name>  # initializes this directory for the scc'
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        'which|w' => 'which scc is available',
        map {($_ => "use $_") } (sort keys %{$self->knownSCC}), # each scc
        );
    }

sub getOptions {
    my $self=shift;
    $self->SUPER::getOptions(@_);

    foreach (%{$self->knownSCC}) {
        $self->options->{'SCC'} = $_ if (exists $self->options->{$_});
        }

    }

sub doCommand {
    my $self=shift;
    $self->SUPER::doCommand(@_);

    vverbose 4,"after getoptions";

    my $done = 0;

    if ($self->options->{'which'}) {
        print join("\n",map { /^SCC::SCC::([^:]+)/; $1} @{$self->whichCanDoThis()})."\n";
        $done=1;
        }

    return if $done;

    if (!$self->options->{'SCC'}) {
        $self->options->{'SCC'} = $self->menuChoice(
        "Choose a scc",
        "scc number",
        [ 
            map { /^SCC::SCC::([^:]+)/; $1 } @{$self->whichCanDoThis()},
        ],
        );
        }
    print "Init for ".$self->options->{'SCC'}."\n";

    my $package =  "SCC::SCC::".$self->options->{'SCC'}."::Commands::".$self->command;
    eval "use $package"; die $@ if $@;
    $package->doCommand;
    }

sub menuChoice {
    my $self=shift;
    my ($heading,$prompt,$choices, $default) = @_;
    # choices can be:
    #   a list: the answer is the choice
    #   a hash: the choice is the value, the answer is the key

    # force to hash
    if (ref($choices) eq 'ARRAY') {
        $choices = { map { ($_ => $_) } @$choices};
        }


    my ($defaultText);
    if ($default) {
        $defaultText = delete $choices->{$default};
        }
    my $i=0;
    my $menu = Term::Menu->new(
        beforetext => $heading,
        aftertext => $prompt.($default ? " (0 for default)" : '').": ",
        tries => 3,
        );
    my $answer = $menu->menu(
        $default ? ($default => [ "* $defaultText" , $i++ ]) : (),
        map {
            ( $_ => [ "  ".$choices->{$_} , $i++ ] )
            } sort keys %$choices
            );
    die "No choice" if ! defined $answer;
    return $answer;
    }


sub sanityCheck {
    my $self=shift;

    my @id = map {chomp; $_} `tla my-id`;
    die 'You need to set your id with "tla my-id xxxx"' if !scalar(@id);

    my %archive;
    my $name;
    foreach (map {chomp; $_} `tla archives`) {
        if (s/^\s+//) {
            $archive{$name} = $_;
            }
        else {
            $name = $_;
            }
        }
    die 'You need to register some archive locations with "tla archive-register..."' if !scalar(%archive);

    my ($default) = map {chomp; $_} `tla my-default-archive`;
    warn "You might want to set a default archive location with 'tla my-default-archive'" if !$default;

    return (\%archive, $default);
    }

sub whichCanDoThis {
    my $self=shift;
    my ($command) = $self =~ /([^:]+)$/;
    
    my %ucommands = map { ($_,undef) } grep { /^SCC::SCC::[^:]+::Commands::$command$/} findallmod('SCC::SCC');
    my @commands = sort keys(%ucommands);

    return \@commands;
    }

sub delegate {}

sub findPrimarySCC {}
1;
