package SCC::SCC::svn::Commands::inventory;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;
    my $filter;
    if ($self->options->{'dir'}) {
        $filter='&& /directory$/';
        }
    elsif ($self->options->{'file'}) {
        # the default is file only!
        $filter='&& /file$/';
        }
    else {
        $filter="";
        }
    my $cmd = "svn info -R | awk '/^Path:/ {path=\$2} /^Node Kind:/ $filter {print path}'";
    system($cmd);
    }

1;
