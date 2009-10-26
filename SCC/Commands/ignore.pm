package SCC::Commands::ignore;
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
    return "$command <options>  [file-name...] # edit (add file-name to) the ignore list";
    }

sub optionDesc {
    my $self=shift;
    return (
        $self->SUPER::optionDesc(),
        # map {($_ => "commit $_") } (sort keys %{$self->knownSCC}), # each scc #FIXME: make an option to "scc"
        );
    }
1;
