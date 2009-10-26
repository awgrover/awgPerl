package HTTP::WebTestScript::Log;
use base qw(Exporter);
@EXPORT    = qw(trace getLog closeLog);

use strict;
use warnings;
no warnings 'uninitialized';

our
	(
	$gDepth,
	$_gLog,
	);
	
sub getLog
	{
	return \*STDERR if !$HTTP::WebTestScript::gLog || $HTTP::WebTestScript::gLogToSTDERR;
	return \*STDOUT if $HTTP::WebTestScript::gLogToSTDOUT;
	
	return $_gLog if $_gLog;
	
	# "unbuffer" stdout if we are logging to a file so our progress indicator works
	select((select(STDOUT), $| = 1)[0]); # perlism
	
	$HTTP::WebTestScript::gLog =~ s|/$||;
	my $logName = "$HTTP::WebTestScript::gLog/results_".HTTP::WebTestScript::timestamp().".xml";
	
	my $fh = IO::File->new(">$logName") || die "Can't open logfile $logName, $!";
	print "# log $0= $logName\n";
	
	$_gLog = $fh;
	return $_gLog;
	}

sub closeLog
	{
	$_gLog->close if $_gLog;
	}

sub trace
	{
	# turn a structure into xml:
	# first arg is tag, rest is attributes and subtags
	# if next part is array or scalar, then it is meant to be content
	# if next part is hash, it is meant to be attributes or sub-tags
	# it's an attribute if scalar, otherwise subtags
	my ($success,$tag,$values,$depth, $leaveOpen) = @_;
	$depth = $gDepth if !defined $depth;
	$depth = "" if !defined $depth;

	my $LOG = getLog();
	
	if (defined($leaveOpen) && $leaveOpen eq 'closePrevious')
		{
		print $LOG "$depth</$tag>\n";
		}
		
	
	if (defined $success)
		{
		$success = $success ? 1 : 0;
		}
	
	my $successAttribute = defined($success) ? " success=\"$success\"" : " success=0";
	
	print $LOG "\n" if $tag eq 'name' || $tag eq 'step' || $tag eq 'forgetCookies'; # formatting

	# stdout progress if going to log
	if ($_gLog) #$HTTP::WebTestScript::gLog)
		{
		print "\n<$tag> ",$values->{'description'}  if ($tag eq 'name');
		print "." if ($tag eq 'step'); 
		}

	print $LOG $depth,"<$tag$successAttribute";
	
	trace_attributes($LOG,$values);
	my $wasContent = trace_directContent($LOG,"$depth\t",$values);
	$wasContent |= trace_children($wasContent,$LOG,"$depth\t",$values);
	
	# end-tag if content
	# else empty tag
	if (!defined $leaveOpen)
		{
		print $LOG
			($wasContent)
			? "$depth</$tag>\n"
			: "/>\n"
			;
		}
	else
		{
		print $LOG ">\n";
		}
	}

sub trace_children
	{
	my ($alreadyClosed, $LOG, $depth, $values) = @_;
	
	return 0 if ref($values) ne 'HASH';
	
	my $rez = 0;
	
	while (my ($k,$v) = each %$values)
		{
		next if ref( $v) ne 'ARRAY';
		
		if (!$rez)
			{
			print $LOG ">\n"; # close tag
			}
		
		trace(1, $k, $v, "$depth\t");
		}
	
	return $rez;
	}
	
sub trace_directContent
	{
	my ($LOG, $depth,$values) = @_;
	
	if (!ref($values))
		{
		print $LOG ">\n"; # close tag	
		print $LOG $depth,$values,"\n";
		}
	elsif (ref($values) eq 'ARRAY')
		{
		print $LOG ">\n"; # close tag	
		foreach (@$values)
			{
			print $LOG $depth,"<value>$_</value>\n";
			}
		}
	elsif (ref($values) eq 'HASH' && exists $values->{'content'})
		{
		print $LOG ">\n"; # close tag	
		print $LOG $depth,$values->{'content'},"\n";
		}
	else
		{
		return 0;
		}
		
	return 1;
	}
	
sub trace_attributes
	{
	my ($LOG, $values) = @_;
	
	return if ref($values) ne 'HASH';

	while (my ($k,$v) = each %$values)
		{
		next if ref $v && ref($v) ne 'Regexp';
		next if $k eq 'content';
		next if !defined $v;
		
		print $LOG ' regex="yes"' if ref($v) eq 'Regexp';
		print $LOG " $k=\"$v\"";
		}
	}

1;
