package Test::Website::Log;
use base qw(Exporter);
@EXPORT    = qw(trace getLog closeLog);

use strict;
use warnings;
no warnings 'uninitialized';
use Carp;
use Verbose;

our
	(
	$gDepth,
	$_gLog,
	);
	
sub getLog
	{
	return \*STDERR if !$Test::WebsiteScript::gLog || $Test::WebsiteScript::gLogToSTDERR;
	return \*STDOUT if $Test::WebsiteScript::gLogToSTDOUT;
	
	return $_gLog if $_gLog;
	
	# "unbuffer" stdout if we are logging to a file so our progress indicator works
	select((select(STDOUT), $| = 1)[0]); # perlism
	
	$Test::WebsiteScript::gLog =~ s|/$||;
	my $logName = "$Test::WebsiteScript::gLog/results_".Test::WebsiteScript::timestamp().".xml";
	
	my $fh = IO::File->new(">$logName") || die "Can't open logfile $logName, $!";
	print "# log $0= $logName\n";
	
	$_gLog = $fh;
	return $_gLog;
	}

sub closeLog
	{
	$_gLog->close if $_gLog;
	}


sub flatten {
    my $d = Data::Dumper->new([$_[0]]);
    $d->Indent(0); $d->Terse(1); $d->Sortkeys(1); $d->Quotekeys(0);
    my $expr = $d->Dump;
    $expr =~ s/^[[{]//;
    $expr =~ s/[}\]]$//;
    return $expr;
    }

sub trace
	{
        my ($ok, $command, $args, %options) = @_;

        local $Test::Builder::Level = $Test::Builder::Level + 1;

        Test::Builder::Module->builder->ok(
            $options{'maybe'}
                ? 1
                : $ok,
            $command 
            . " ". flatten($args)
            .( (!$ok)
                ? $options{'because'}
                    ? ". failed because: ". $options{'because'}
                    : ". failed"
                : "")
            );

        {
        local @Test::Website::Log::CARP_NOT = qw(Test::Website Test::Website::Element);
        croak $options{'because'} || "failed" if !$ok && !$options{'maybe'};
        }
        return $ok;
	}

1;
