package SCC::BaseCommand;

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use File::Basename;
use Module::Find;

use Verbose;
*kVerbose = *SCC::kVerbose;

our $Options = {}; # not used

sub options {
    my $self=shift;
    no strict 'refs';
    return ${"$self\::Options"};
    use strict 'refs';
    }

sub usage {
    # override by returning a usage string
    my $self=shift;
    die "Specify usage in $self";
    }

sub optionDesc {
    # Override by returning ( super::optionDesc(), 'xx'=>'yy'... )
    my $self=shift;
    our ($command) = (ref($self) || $self) =~ /([^:]+$)/;
    $command =~ s/_/-/g;

    return (
        '' => $self->usage($command),
        'help|h|H' => 'this',
        'usage' => 'just usage',
        );
    }

sub doCommand {
    my $self=shift;
    verbose "DO";

    $self->getOptions();
    vverbose 4,"after getoptions";

    my $scc = $self->findPrimarySCC();
    $self->delegate($scc);
    }

sub getOptions {
    my $self=shift;
    use Carp; confess if !$self;
    my $options =
    awgrover::Getopt::GetOptions (
        $self->optionDesc()
        );

    exit 1 if !$options;

    no strict 'refs';
    ${"$self\::Options"} = $options;
    use strict 'refs';

    if ($self->options->{'usage'}) {
        my %optionDesc = $self->optionDesc();
        print $0," ".$optionDesc{''}."\n";
        exit 0 if $awgrover::Getopt::gExitOnHelp;
        }
    }



# The list we know
our %KnownSCC = (
    # name (for SCC_PRIMARY, etc.) => 
    cvs => { control_dir => 'CVS', uptree => 0, command => 'cvs commit -m' },
    tla => { control_dir => '{arch}', uptree => 1, command => 'tla commit -s' },
    # svn
    git => { control_dir => '.git', uptree => 1, command => 'git commit -a -m', command_with_files => 'git commit -m' },
    svn => { control_dir => '.svn', uptree => 1, command => 'svn commit -m' }
    );
our %Dir2SCC;
    @Dir2SCC{map {$KnownSCC{$_}->{'control_dir'}} keys %KnownSCC} = keys %KnownSCC;


sub knownSCC {
    my $self=shift;
    return  \%KnownSCC;
    }

# look for all the scc's
# pick the only one, or, the one pointed to by .scc.primary, or the $SCC_PRIMARY
# hunt up the tree

sub linkOrEnv {
    my $self=shift;
    my ($dir) = @_;

    # use link first
    if (-l $dir."/".'.scc.primary') {
        my $rez = $Dir2SCC{readlink($dir."/".'.scc.primary')};
        if ($self->options->{'where'})
            {
            print "$rez from $dir/.scc.primary\n";
            system("ls -l $dir/.scc.primary");
            exit 0;
            }
        return $rez;
        }

    # then env var
    if ($ENV{'SCC_PRIMARY'}) {
        my $rez = $ENV{'SCC_PRIMARY'} if (-d $dir."/".$KnownSCC{$ENV{'SCC_PRIMARY'}}->{'control_dir'});
        if ($rez && $self->options->{'where'})
            {
            print "$rez from \$SCC_PRIMARY\n";
            exit 0;
            }
        return $rez if $rez;
        }
    return undef;
    }

sub findPrimarySCC {
    my $self=shift;

    my $rez = $self->linkOrEnv(".");
    vverbose 2,"found in link/env $rez" if $rez;
    return $rez if $rez;
    # then hunt
    my @possible = grep {-d $KnownSCC{$_}->{'control_dir'}} keys %KnownSCC;
    vverbose 2,"Consider ones at ./ ",join(", ",@possible);
    die "More than one scc: ".join(",",@possible),". Set \$SCC_PRIMARY or .scc.primary link (at ".cwd().")"
        if scalar(@possible) > 1;
    
    if (scalar(@possible) == 1) {
        my $scc = $possible[0];
        vverbose 2,"./ is root for $scc";
        if ($self->options->{'where'})
            {
            print "$scc at ./\n";
            vverbose 2,"exited";
            exit 0;
            }
        return $scc if ($KnownSCC{$scc}->{'uptree'}); # must be at "root" of project
        }

    my @uptree = $self->huntUpTree(dirname(cwd()));
    vverbose 2,"Consider ones above us ",join(", ",@uptree);

    die "More than one scc: ".join(",",@uptree),". Set \$SCC_PRIMARY or .scc.primary link (at ".cwd()." or above)"
        if scalar(@uptree) > 1;

    push @possible,@uptree; 

    use Carp; confess "No scc control-dirs found\n" if ! scalar(@possible);
    return $uptree[0] if (scalar(@uptree) == 1);
    vverbose 2,"No scc above us, so use the per-dir scc at ./";
    return $possible[0];
    }

sub huntUpTree {
    my $self=shift;
    my ($up) = @_;
    return () if !$up;

    my $rez = $self->linkOrEnv($up);
    return $rez if $rez;

    my @possible = grep {
        $KnownSCC{$_}->{'uptree'} &&
        -d $up."/".$KnownSCC{$_}->{'control_dir'}
        } keys %KnownSCC;
    
    if (scalar(@possible)) {
        if (scalar(@possible)==1 && $self->options->{'where'})
            {
            print $possible[0]." at $up\n";
            vverbose 2,"exited";
            exit 0;
            }
        return @possible;
        }
    else {
        return $self->huntUpTree(dirname($up)) unless $up eq '/';
        return ();
        }
    }

sub command {
    my $self=shift;
    my ($command) = $self =~ /([^:]+)$/;
    return $command;
    }

sub whichCanDoThis {
    # return a list of scc-names that can do "this" command: SCC::SCC::$sccname::$commandName
    my $self=shift;
    my $command = $self->command;
    
    my %ucommands = map { ($_,undef) } grep { /^SCC::SCC::[^:]+::Commands::$command$/} findallmod('SCC::SCC');
    my @commands = sort keys(%ucommands);

    return \@commands;
    }

sub delegate {
    my $self=shift;
    my ($sccName) = @_;

    my $command = $self->command;

    my ($possible) = grep { /^SCC::SCC::$sccName\::/ } @{ $self->whichCanDoThis() };
    die "SCC::SCC::$sccName\::Commands::$command doesn't exist" if !$possible;

    # delegate rest of command to the particular scc
    my $package = "SCC::SCC::$sccName\::Commands::$command";
    eval "use $package"; die $@ if $@;
    no strict 'refs';
    ${"$package\::Options"} = $self->options;
    use strict 'refs';
    $package->doCommand(); 
    }

1;
