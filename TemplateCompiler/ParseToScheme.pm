package TemplateCompiler::ParseToScheme;
use base qw(TemplateCompiler::Parse);

=pod

Compiles a Template to a guile module.

Executing the template requires a module that has the helper
functions (like "interpolate" etc.).

= Usage

From the command line:

	perl -mTemplateCompiler::ParseToScheme -e 'TemplateCompiler::ParseToScheme->compile' template > compile template

= Differences

Should allow scheme tokens like "blah-blah".

See the helper module for other differences:

False is determined by (not (trueish value)) from module (awg function). 
The expected empty/null values are false: e.g. nil, '(), 0, "", #f, etc.

Since guile doesn't have distinct types for some things, we guess:
* FIXME: rules for hash-key, array-index, etc.

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use awgrover::Getopt;
use Verbose;

sub compile 
	{
	vverbose 1,"ParseToScheme start\n";
	my $switches = awgrover::Getopt::GetOptions
		(
		'' => 'Compile a template to a guile form (requires helper functions)',
		'help|h|H' => 'this',
		'moduleName=s' => 'Use this module name if no file-name',
		'trimFinalEOL' => 'Drop the final EOL',
                'leaveComments' => "don't strip comments",
		);
	exit 0 if $switches->{'help'};

	# vverbose 0,"ARGV ",join(",",@ARGV),"\n";
	if ($ARGV[0] eq '-') {shift @ARGV}

	my $file = $ARGV[0];	
	# FIXME: remove newlines
	print "(define-module (awg:template:awg "
		. ($file || $switches->{'moduleName'})
		."))\n";
	print "(use-modules (awg compiled-template))\n";

	my $input = join("",<>);
	if ($switches->{'trimFinalEOL'})
		{
		chomp $input;
		}
	
	my $parser = __PACKAGE__->new
		(
		string => $input, 
		provenance => $file,
                $switches->{'leaveComments'} ? (removeComments => 0) : (),
		);
	$parser->parse;
	foreach (@{$parser->result})
		{
		print $parser->displayOrIdentity($_);
		}
	vverbose 1,"ParseToScheme finished\n";
	}

sub quoteToken
	{
	shift;
	return "'".shift;
	}

sub quote
	{
	my $self=shift;

	$_[0] =~ s|\\|\\\\|sg;
	$_[0] =~ s|"|\\"|sg ;
	return '"' . $_[0] .'"';
	}

sub displayOrIdentity
	{
	my $self=shift;
	
	if ($_[0] =~ /^\(_interpolate/ || $_[0] =~ /^"/)
		{
		"(display ".$_[0].")";
		}
	else
		{
		$_[0];
		}
	}

sub applyInterpolate
	{
	my $self=shift;
	my ($fn, $provenance, $line, $expr) = (shift, shift, shift, shift);
	$self->apply($fn,"templateInterpreter",$provenance, $line, $expr, "'()", 
		@_);
	}

sub apply
	{
	my $self=shift;
	my ($fn) = shift;

	return
		"($fn "
		.join(" ",@_)
		.")";
	}

our %gComparison = # < and > work for strings, EQ uses rhsType to decide operator
    ( EQ => 'equalish?', LT => '<', GT => '>' );
our %gEquality = # Need different ops for EQ based on type
    ( '"' => 'equal?', '0' => '=' );

sub constructIf
	{
	my $self=shift;
	my ($fnOpen, $ifBody, $elseBody) = @_;

        confess() if !ref $fnOpen; use Carp;
	my ($not, $lhs, $op, $rhsType, $rhs) = @$fnOpen{qw(not lhs op rhsType rhs)};

	# vverbose 0, "#-#-# ",Dumper($fnOpen),"\n"; use Data::Dumper;
        # vverbose 0, "ConsIf lhs:",$lhs," op:",$op," rhs:(",$rhsType,")",$rhs,"\n" if $rhs;

	# In scheme, we have to use (trueish) to get our "true"
	# behavior.
	# But, we only need to do that if there is no comparison-op

	my $expr = $lhs;
	if ($op)
		{
		$op = # ($op eq 'EQ') ? 
                    $gComparison{$op}
                    # : ( $gComparison{$op} || 'equal?' )
                    ;
                $rhs = $self->quote($rhs) if $rhsType eq '"';
		$expr = "($op $expr $rhs)"; # FIXME: translate
		}
	else
		{
		$expr = "(trueish $expr)";
		}

	$expr = "(not $expr)" if $not;
	
	my $ifExpr =
		"(if $expr "
			.$self->bodyOrUndef($ifBody)
			." ".$self->bodyOrUndef($elseBody)
		.")";
	
	# vverbose 0,"\t$ifExpr\n";
	$self->appendParse($ifExpr);
	}

sub constructInclude
	{
	my $self = shift;
	my ($protocol) = shift;

	die "Protocol '$protocol' not supported"
		if ( $protocol ne 'file:' );

	$self->appendParse(
		$self->apply("_include", 'templateInterpreter', 
			$self->stringAppend(@_)
			)
		);
	}

sub stringAppend
	{
	my $self=shift;
	my $ct = scalar @_;
	if ($ct == 0)
		{
		my $x = "";
		return $self->quote($x);
		}
	elsif ($ct == 1)
		{
		return $_[0];
		}
	else
		{
		return "(string-append "
			.join(" ",@_)
			.")";
		}
	}

sub constructSelect
	{
	my $self=shift;
	my ($xpath, $xmlFileName, $xslFileName, $text) = @_;

	my $protocol = 'file:';
	$self->appendParse(
		$self->apply(
			'_xslt',
			'templateInterpreter',
			$self->quote($self->provenance),
			$self->line,
			$self->quote($text),
			$xpath eq "" ? '""' : $xpath, 
			$self->stringAppend(@$xmlFileName), 
			$self->stringAppend(@$xslFileName))
		);

	vverbose 4,$self->result->[-1],"\n";
	}

sub constructIterator
	{
	my $self=shift;
	my ($open, $parts) = @_;

	my $result =
		"(_iterate "
		.join(" ",
			,"templateInterpreter"
			,$open->{'itor'}
			,$open->{'itor'}."_index"
			,"(lambda () ".$self->bodyOrUndef($parts).")"
			,$open->{'collection'}
			)
		.")";

	#vverbose 0,$result,"\n";
	$self->appendParse($result);
	}


sub bodyOrUndef
	{
	my $self=shift;
	my ($body) = @_;

	if (scalar(@$body))
		{
		my @fixupChunks = map {$self->displayOrIdentity($_)} @$body;
		my $bodyExpr = join(" ",@fixupChunks);
		if ( scalar (@$body) > 1)
			{
			$bodyExpr = "(begin $bodyExpr)";
			}
		return $bodyExpr;
		}
	else
		{
		return '""'
		}
	}
1;
