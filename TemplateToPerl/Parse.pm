package TemplateToPerl::Parse;
use base qw(Class::New);

=pod

A functional parser, abstract-syntax-tree.

=head1 Initialize

	$state = TemplateToPerl::Parse(string=>$str, provenance=>$fileName);

=head1 production

Each piece of the syntax (a production) does this:

	my (@pieces) = $state->remainder =~ /regex/;
	if @pieces, 
		$state->remainder( part not parsed );
		$state->appendParse( @pieces to objects ); # AST
		$state->addLinesConsumed( newlines-consumed);
		return $state;
	else
		$state->syntaxError(some explanation);
		return  undef

A production may also be a Sequence or Alternation.
				
=head1 Sequence

	production1($s)
	&& production2($s)
	...

=head1 Alternation

	production1($s)
	|| production2($s)

=head1 Repetition (tail)

zero or more

	( sameProduction($s) || $self->noSyntaxError )

one or more

	sameProduction($s)

=head1 Errors

=head2 Discipline

1st approximation: Die on any syntax error, see various exceptions in TemplateToPerl.

2nd approximateion: Die, but catch at _twiddle, accumulate error, and continue at eol. Report at end of parse.

3rd approximate: Die, but catch at parent (usually _twiddle), accumulate, and continue after end of expression (usually after }} ).

=head2 Special cases

These are semantic errors, not syntax, but I haven't separated out this level of semantics:

Unclosed tags, or extra close-tags, are automatically turned into errors at the end of the parse, based on left-over records in @nesting.
	
=head1 Tweaking the syntax error

	( production($s) || $self->syntaxError("expected ...., found ".$self->remainder) )
	&& undef
				
=head1 Result

The $state->result is the array of data passed to appendParse().

In our case, the result is perl-code, carefully constructed such that each line of the result corresponds to the line of input.

=head1 Our Syntax

Our syntax is for parsing {{}} patterns. The whole point of this is to allow nested
interpolation: {{A.{{B}}.C}}, probably most useful for includes.

	Template = (Twiddle | NonTwiddle)* and whatever-to-skip-comments
	NonTwiddle = (not {{ or {{{ ) +
	Twiddle = HTMLEscapedTwiddle | URLEscapedTwiddle
	HTMLEscapedTwiddle = {{TwiddleContent}}
	URLEscapedTwiddle = {{{TwiddleContent}}}
	TwiddleContent = $Slot
		| ITERATE $Slot $IterName
		| /ITERATE
		| IF $Slot | IF !$Slot | IF $slot eq $slot | IF $slot eq 'str'
		| /IF
		| INCLUDE FileName
	Slot = (Token | Twiddle) .Slot*
	Token = Alpha followed by AlphaNumeric*
	IterName = Token
	
=head1 UnitTests

This module has internal unit-tests.

	perl -mUnitTestInLine -e UnitTestInLine::run Parse.pm

(cd to the directory, that containts this module, somewhere in your PERL5LIB)

See 'perldoc UnitTestInLine'

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Carp;
use Verbose;
$kVerbose=0;

use TemplateToPerl::Exceptions;

our %gInterpolateFunction = 
	(
	url => '_interpolateUrlEscaped',
	html => '_interpolate',
	none => '_interpolateRaw',
	);
	
use Class::MethodMaker get_set=>[qw(
	string remainder
	provenance line characterPosition  
	syntaxError result 
	nesting compileErrors
	)];

=test new
	Sanity
		my $string = "A bc a3 a3b";
		my $rez = TemplateToPerl::Parse->new($string);
		assertTest($rez,"Expected something back from TemplateToPerl::Parse->new") &&
		assertTest(ref($rez),"Expected a ref from TemplateToPerl::Parse->new") &&
		assertEQ(ref($rez),'TemplateToPerl::Parse',"Correct class");

=cut

sub preInit
	{
	my $self=shift;
	$self->result([]);
	$self->line(1);
	$self->characterPosition(1);
	$self->nesting([]);
	$self->compileErrors([]);
	}

sub init
	{
	my $self=shift;
	$self->remainder($self->string);
	vverbose 1,"PARSE '".$self->string."'\n";
	}

sub appendParse
	{
	my $self = shift;
	push @{$self->result}, @_;	
	return $self;	
	}

sub noSyntaxError
	{
	my $self = shift;
	$self->syntaxError(undef);
	return $self;
	}

sub remainderHead
	{
	return substr(shift->remainder,0,20)."...";	
	}	

sub sugar
	{
	# a production to consume sugar
	my $self=shift;
	my ($regex,$syntaxMessage,$startingString) = @_;
	
	my ($token) = $self->pattern($regex,$syntaxMessage,$startingString);
	return (defined $token)
		? $self
		: undef;	
	}

sub updateRemainder
	{
	my $self=shift;
	
	my $beforeLength = length($self->remainder);
	my $afterLength = length($_[0]);
	my $charactersConsumed = $beforeLength - $afterLength;
	
	# try to avoid $' and string copy
	# find last line
	if (substr($self->remainder,0,$charactersConsumed) =~ /^(.*\n)/gs) # want greedy, last eol
		{
		$charactersConsumed = $charactersConsumed - length($1);
		}
	
	$self->remainder( $_[0] );
	$self->characterPosition($self->characterPosition 
		+ $charactersConsumed);
	}

sub lookaheadSugar
	{
	my $self=shift;
	my ($regex,$message) = @_;
	
	if ($self->remainder !~ /^($regex)/s)
		{
		$self->syntaxException("Expected $message, found '".$self->remainderHead."'");
		}
	return $self;
	}
					
sub pattern
	{
	# a production skeleton: parse a simple regex
	# use in body of a production, 
	# sets remainder or syntaxerror,
	# returns matched patterns or undef
	my $self=shift;
	my ($regex, $syntaxMessage,$startingString) = @_;
	
	
	my @parse = $self->remainder =~ /^($regex)(.*)/s; 
	vverbose 8,"\t\t",$self->remainderHead,"=~/^($regex)(.*)/ as '",join(",",@parse),"'\n";

	if (scalar @parse) 
		{
		$self->updateRemainder( pop @parse );
		return @parse;
		}
	else
		{
		my $found = $self->remainderHead;
		$self->syntaxError(
			TemplateToPerl::SyntaxException->new(
				message=> "Expected $syntaxMessage, found '$found'"
					. ($startingString ? " in '$startingString'" : ""),
				fileName => $self->provenance,
				line => $self->line, 
				characterPosition => $self->characterPosition,
				child => $self->syntaxError,
				)
			);
		return  undef;
		}
	}

sub setSyntaxError
	{
	my $self=shift;
	my ($message,$startingStr,$childError) = @_;
	
	$self->syntaxError(
		TemplateToPerl::SyntaxException->new(
			message=> "Expected $message, found '$startingStr'",
			fileName => $self->provenance,
			line => $self->line, 
			characterPosition => $self->characterPosition,
			child => $childError,
			)		
		);
	return undef;
	}

sub syntaxException
	{
	my $self=shift;
	my ($message,$child,$characterPosition) = @_;
	
	my $e = TemplateToPerl::SyntaxException->new(
		message=> $message,
		fileName => $self->provenance,
		line => $self->line, 
		characterPosition => $characterPosition || $self->characterPosition,
		child => $child,
		);
	$self->syntaxError($e);
	die $e;
	}
	
sub accumulateNestingErrors
	{
	my $self=shift;
	
	vverbose 2,"## first tagNotClosed is ",%{$self->nesting->[0] ||{}},"\n";
	push @{$self->compileErrors},
		map {
			TemplateToPerl::TagNotClosedError->new(%$_);
			} @{$self->nesting};
	}

sub throwAccumulatedErrors
	{
	my $self=shift;
	
	my @cerrors = @{$self->compileErrors};
	vverbose 2,"### first compileError is ".$cerrors[0],"\n";
	if (scalar @cerrors)
		{
		die TemplateToPerl::TemplateError->new(
			fileName => $self->provenance,
			line => 0,
			message => "\n\t".join("\t", @cerrors)."\t"
			);
		}
	}

###
# Productions below here
###

sub parse
	{
	my $self=shift;
	
	$self->_template || return;
	
	vverbose 2,"EOF, lines ",$self->line.", open tags ".scalar(@{$self->nesting})."\n";
	
	# check nesting errors
	
	if ($self->remainder)
		{
		$self->syntaxException("Expected EOF"); 
		}
	
	$self->accumulateNestingErrors;
	$self->throwAccumulatedErrors;

	return $self;	
	}
		
sub _template
	{
	my $self=shift;
	
	$self->_null && return $self;
	
	return
	($self->_comment || $self->_body || $self->_twiddle)
	&& $self->_template;
	
	}

sub _null
	{
	my $self=shift;
	
	# tried /^$/s, but matched "\n"!
	return ($self->remainder !~ /./s) && $self;
	}
	
sub _body
	{
	my $self = shift;
	
	vverbose 2,"\tbody (".$self->line.") ".$self->remainderHead."\n";
	
	my $body;
	if ($self->remainder =~ /<!--|{{{?/s)	# comments or {{}}
		{
		$body=$`;
		$self->updateRemainder($&.$');
		}
	else
		{
		$body=$self->remainder;
		$self->updateRemainder(undef);
		}
	
	vverbose 2,"\t\tas ".substr($body,0,20)."...\n";
	return undef if $body eq '';
		
	# HTML Chunk, quote & perl escape
	my $eolCt = $body =~ tr/\n/\n/;
	vverbose 3,"\tlines consumed $eolCt\n";
	$self->line($self->line + $eolCt);
	$body =~ s|\\|\\\\|sg;
	$body =~ s|'|\\'|sg ;
	$body =~ /(.*)/s;
	my $eol = chomp $body;
	$self->appendParse(
		"'".$body.("\n" x $eol)."'"
		);
	
	$self->noSyntaxError;
	vverbose 1,"\tPARSED (".$self->line.")\n";
		
	return $self;
	}	

sub _comment
	{
	my $self=shift;
	
	return $self->sugar('<!--') && $self->_toEndOfComment;
	}
							
sub _toEndOfComment
	{
	my $self=shift;
	
	my $regex = '-->';
	my $syntaxMessage = 'a closing comment (-->)';
	
	my @parse = $self->remainder =~ /$regex(.*)/s; 
	vverbose 8,"\t\t",$self->remainderHead,"=~/^($regex)(.*)/ as '",join(",",@parse),"'\n";

	if (scalar @parse) 
		{
		$self->updateRemainder( pop @parse );
		#$self->appendParse(@parse);
		return $self;
		}
	else
		{
		my $found = $self->remainderHead;
		$self->syntaxError(
			TemplateToPerl::SyntaxException->new(
				message=> "Expected $syntaxMessage, found '$found'",
				fileName => $self->provenance,
				line => $self->line, 
				characterPosition => $self->characterPosition,
				child => $self->syntaxError,
				)
			);
		return  undef;
		}
	}

sub _twiddle
	{
	my $self = shift;
	
	vverbose 2,"\ttwiddle".$self->remainderHead."\n";
	
	my $startingStr = $self->remainderHead;
	my $startingAmount = length($self->remainder)-2;
	my $twiddleStart = $self->characterPosition;
	
	$self->sugar('{{',"{{...}}") || return;
	
	vverbose 3,"\@$startingAmount (char $twiddleStart)\n";
	
	eval
		{
		# $xxxx
		if (
			# {{{{ => raw (no escaping!)
			($self->sugar('{{') && $self->_dollarSlot(escaping=>'none') 
				&& $self->lookaheadSugar('}}}}',"fourth } for no-escaped slot")
				&& $self->sugar('}}')
				)
			# {{{ => url escape
			|| ($self->sugar('{') && $self->_dollarSlot(escaping=>'url') 
				&& $self->lookaheadSugar('}}}',"third } for url-escaped slot")
				&& $self->sugar('}')
				)
			|| $self->_dollarSlot 
			|| ((vverbose 6,"\t\tnot \$slot\n"),undef) )
			{vverbose 2,"\tdollar slot!\n"}

		# IF $a
		elsif (($startingAmount == length($self->remainder) || ((vverbose 8,"\t\t\@".length($self->remainder)."\n"),undef)) # i.e. "none consumed"
		&& (($self->sugar('IF ',"IF (IF ...)") && $self->_tag_if)))
			{
			vverbose 2,"\tIf!\n"
			}

		# ELSE
		elsif ($startingAmount == length($self->remainder) # i.e. "none consumed"
		&& ($self->sugar(qr/ELSE/,"ELSE (ELSE)") && $self->_tag_else))
			{
			vverbose 2,"\t/ELSE\n";
			}
	
		# /IF
		elsif ($startingAmount == length($self->remainder) # i.e. "none consumed"
		&& ($self->sugar(qr/\/IF/,"/IF (/IF)") && $self->_tag_close_if))
			{
			vverbose 2,"\t/IF!\n";
			}
	
		# ITERATE $a $b
		elsif ($startingAmount == length($self->remainder) # i.e. "none consumed"
		&& (($self->sugar(qr/ITERATE\s+/,"ITERATE (ITERATE \$collection \$itor)") 
			&& $self->_tag_iterate)))
			{
			vverbose 2,"\tIterate!\n"
			}

		# /ITERATE
		elsif ($startingAmount == length($self->remainder) # i.e. "none consumed"
		&& ($self->sugar(qr/\/ITERATE/,"/ITERATE (/ITERATE)") && $self->_tag_close_iterate))
			{
			vverbose 2,"\t/Iterate!\n";
			}
	
		# nothing consumed, didn't match anything
		elsif ($startingAmount == length($self->remainder))
			{
			vverbose 2,"\tAFAILED $startingStr\n";
			$self->syntaxException("Expected a valid {{...}} found ".$startingStr,undef,$twiddleStart);
			return undef;
			}
		};
	
	# non syntax error
	if ($@)
		{
		if (!ref($@) || !$@->isa('TemplateToPerl::TemplateError'))
			{
			warn "#####ref ".ref($@);
			die $@;
			}

		# some consumed, but syntax failed
		elsif ($startingAmount != length($self->remainder))
			{
			vverbose 2,"\tFAILED $startingStr\n";
			$self->syntaxException("Expected a valid {{...}} found ".$startingStr
				,$self->syntaxError
				,$twiddleStart);
			return undef;
			}

		# nothing consumed, didn't match anything
		elsif ($startingAmount == length($self->remainder))
			{
			vverbose 2,"\tFAILED $startingStr\n";
			$self->syntaxException("Expected a valid {{...}} found ".$startingStr,undef,$twiddleStart);
			return undef;
			}
		}	
			
	return 
	(	$self->sugar('}}',"a closing }}" ,$startingStr)
		|| ((vverbose 2,"\tFAILED $startingStr\n")
			,$self->syntaxError->characterPosition($twiddleStart)
			, die $self->syntaxError
			)
	)
	&& ((vverbose 1,"\tPARSED, next=",$self->remainderHead,"\n"),1)
	&& $self->noSyntaxError() && $self
	;
	}

sub _tag_else
	{
	my $self=shift;
	
	my $nesting = $self->nesting->[-1];
	
	# Only 1 else per if
	if (exists $nesting->{'elseLocation'})
		{
		push @{$self->compileErrors}, 
			TemplateToPerl::ExtraCloseTagError->new(
				fileName=>$self->provenance,
				line=>$self->line, 
				characterPosition => $self->characterPosition,
				tag => 'ELSE',
				expression=>$self->remainderHead, 
				);
		}
	
	$self->checkCloseTag('IF','dontpop','ELSE');
	
	$nesting->{'elseLocation'} = $#{$self->result};
	return $self;
	}
	
sub _tag_close_if
	{
	my $self=shift;
	
	my $nesting = $self->nesting->[-1];
	$self->checkCloseTag('IF');
	
	vverbose 3,"\t(start..end): ",$nesting->{'resultLocation'}
		,"..",$#{$self->result},"\n";
	my $exprStart = $nesting->{'resultLocation'};
	my $ifStart = $exprStart+1;
	my $elseStart = exists ($nesting->{'elseLocation'}) && ($nesting->{'elseLocation'}+1);
	my $last = $#{$self->result};
	my $ifLast = $elseStart ? $elseStart-1 : $last;
	
	vverbose 3,"\tTake results($ifStart...$elseStart...$last)\n";
	
	my $fnOpen = $self->result->[$exprStart];
	my @ifBody = @{$self->result}[$ifStart..$ifLast];
	my @elseBody = 
		$elseStart
		? @{$self->result}[$elseStart..$last]
		: ('undef',);
	
	delete @{$self->result}[$exprStart..$last];

	vverbose 8,"\t\t=> ",@ifBody,"\n";
	
	$self->appendParse("( ".$fnOpen
		." ? (".join(".",@ifBody).") : (".join(".",@elseBody).") )"
		);
	return $self;
	}
	
sub _tag_if
	{
	my $self=shift;
	my ($startingStr) = @_;
	

	my $sofar = scalar(@{$self->result});
	
	push @{$self->nesting}, 
		{
		fileName=>$self->provenance,
		line=>$self->line, 
		characterPosition => $self->characterPosition,
		tag=>'IF',	# FIXME: should be a reverse lookup
		expression=>$startingStr, 
		};
	my $nesting = $self->nesting->[-1]; # so we can add info to this frame
	vverbose 3,"\tdepth=",scalar(@{$self->nesting}),", resultLocation=",scalar($#{$self->nesting}),"\n";
	
	my $isNot = 0;
	my $cmp = undef;
	
	(($self->sugar('!',"'!'") && ($isNot=1)) || $self)  #optional !
	&& ($self->_dollarSlot
		|| $self->syntaxException("Expected slot (\$name...) found '$startingStr'")
		)
	&& ( ($cmp = $self->_if_tag_cmp($startingStr)) || $self) #optional
	&& ($self->noSyntaxError || $self)
	|| return;

	# compose & close fn
	# expression looks like ( ( (expr) ? 1 : undef) && if-body)
	# {{IF $a}} = ( (expr) ? (if-body) : (else-body) )
	# {{IF !$a}} = ( ((expr) ? undef : 1) ? (if-body) : (else-body) )
	# ( (expr) ? (if-body) : (undef) )
	
	my $andNow =$#{$self->result};
	
	my $result = join("xxx",@{$self->result}[$sofar..$andNow]); # only 1
	if ($cmp)
		{
		$result = "$result$cmp";
		}
	if ($isNot)
		{
		$result = "($result) ? undef : 1";
		}
		
	vverbose 2,"\tIf ".$self->provenance."@".$self->line
		." ($sofar..$andNow, for IF=".$nesting->{'resultLocation'}.") "
		.$result,"\n";
	
	# Replace the bits with the synthesized fn-call
	delete @{$self->result}[$sofar..$andNow];
	$self->appendParse ("($result)"); # let _tag_close_if do the rest
	
	# Note location so that close_if can consume intermediate pieces
	$nesting->{'resultLocation'} = $#{$self->result};

	return $self;	
	}

sub _if_tag_cmp
	{
	my $self=shift;
	my ($startingStr) = @_;
	
	# Optional, so just fail if nothing there
	$self->sugar(qr/\s+eq\s+/) || return undef;
	
	$self->_dollarSlot 
	|| $self->_quotedString 
	|| $self->syntaxException(
		'Expected "IF $slot eq $slot" or "IF $slot eq \'...\'", found '
		."'$startingStr'")
	;
	
	vverbose 2,"\t\tcmp expression @".$#{$self->result}.", ",$self->result->[-1]."\n";
	my $arg = delete $self->result->[-1];
	return " eq $arg ";
	}

sub _quotedString
	{
	my $self=shift;
	
	my ($string) = $self->pattern(qr/'[^']*'/);
	return (defined $string)
		? $self->appendParse($string)
		: undef;	
	}
			
sub checkCloseTag
	{
	my $self=shift;
	my ($tag,$dontPop,$actualCloseTag) = @_;
	
	if (!scalar @{$self->nesting})
		{
		push @{$self->compileErrors}, 
			TemplateToPerl::ExtraCloseTagError->new(
				fileName=>$self->provenance,
				line=>$self->line, 
				characterPosition => $self->characterPosition,
				tag => $actualCloseTag || ("/".$tag),
				expression=>$self->remainderHead, 
				);
		}
	
	else
		{	
		my $lastNest = $self->nesting->[-1];
		if ($lastNest->{'tag'} ne $tag)
			{
			push @{$self->compileErrors},
				TemplateToPerl::TagNestingError->new(%$lastNest);
			}
			
		else
			{
			pop @{$self->nesting} unless $dontPop;
			}
		}
	
	}
		
sub _tag_close_iterate
	{
	my $self=shift;
	
	my $nesting = $self->nesting->[-1];
	$self->checkCloseTag('ITERATOR');
	
	my $start=$nesting->{'resultLocation'};
	my $last = $#{$self->result};
	vverbose 3,"\tTake results($start...$last)\n";
	
	my ($fnOpen,@parts) = delete @{$self->result}[$start..$last];

	vverbose 8,"\t\t=> ",@parts,"\n";
	
	$self->appendParse($fnOpen.join(".",@parts)."})");
	return $self;
	}
	
sub _tag_iterate
	{
	my $self=shift;
	my ($startingStr) = @_;
	

	my $sofar = scalar(@{$self->result});
	
	push @{$self->nesting}, 
		{
		fileName=>$self->provenance,
		line=>$self->line, 
		characterPosition => $self->characterPosition,
		tag=>'ITERATOR',	# FIXME: should be a reverse lookup
		expression=>$startingStr, 
		};
	my $nesting = $self->nesting->[-1]; # so we can add info to this frame
	vverbose 3,"\tdepth=",scalar(@{$self->nesting}),", resultLocation=",scalar($#{$self->nesting}),"\n";
	
	($self->_dollarSlot
		|| $self->syntaxException("Expected collection (\$name...) found '$startingStr'")
		)
	&& ($self->sugar(qr/\s+/) 
		|| $self->syntaxException("Expected space (\$collection \$name) found '$startingStr'")
		)
	&& (($self->sugar('\\$','$slot') && $self->_slotp(simpleSlot=>1)) 
		|| $self->syntaxException("Expected iterator (\$collection \$name) found '$startingStr'"
			,$self->syntaxError)
		)
	&& ($self->noSyntaxError || $self)
	|| return;

	# compose & close fn
	my $andNow =$#{$self->result};
	my $result = 
		"\$self->_iterate('"
		.$self->provenance
		."',".$self->line
		.",".join(",",@{$self->result}[$sofar..$andNow])
		.", sub {";
	;
	
	vverbose 2,"\tIterate ".$self->provenance."@".$self->line
		." ($sofar..$andNow, for /iterate=".$nesting->{'resultLocation'}.") "
		.$result,"\n";
	
	# Replace the bits with the synthesized fn-call
	delete @{$self->result}[$sofar..$andNow];
	$self->appendParse ( $result );
	
	# Note location so that close_iterate can consume intermediate pieces
	$nesting->{'resultLocation'} = $#{$self->result};

	return $self;	
	}
	
sub _dollarSlot
	{
	my $self=shift;
	# pass @_ through to _slot (and _slotp)
	
	return $self->sugar('\$',"Slot (\$name...)") && $self->_slot(@_);
	}
			
sub _twiddleSlot
	{
	my $self = shift;
	
	vverbose 2,"\ttwiddle slot ".$self->remainderHead."\n";
	
	return
	$self->sugar('{{',"{{}}")
	&& (
		$self->_dollarSlot
		)
	&& $self->sugar('}}',"A closing }}")
	;	
	}
				
sub _slot
	{
	# 	Slot = (Token | Twiddle) .SlotOrNumber*
	my $self=shift;
	my %args = @_;
	my ($escaping) = delete $args{'escaping'};
		$escaping = 'html' if !$escaping;
		
	# pass %args through to slotp
	
	my $sofar = scalar(@{$self->result});
	my $expr = $self->remainderHead;
	
	$self->_slotp(%args) || return undef;	
	
	# compose & close fn
	my $andnow =$#{$self->result};
	my $result = $self->makeInterpolate($escaping,$expr,@{$self->result}[$sofar..$andnow]);
		
	vverbose 4,"\tSlot ".$self->provenance."@".$self->line
		." ($sofar..$andnow) "
		.$result,"\n";
	
	# Replace the bits with the synthesized fn-call
	delete @{$self->result}[$sofar..$andnow];
	$self->appendParse ( $result );
		
	return $self;
	}

sub makeInterpolate
	{
	my $self=shift;
	my ($escaping,$expr) = (shift, shift); # @_ is slot
	
	$expr = s/\\/\\\\/g; 
	$expr = s/'/\\'/g;
	return
		# fn open
		'$self->'.$gInterpolateFunction{$escaping}.'('
			."'".$self->provenance
			."'," .$self->line
			.",'$expr'"
		# args
		. ",".join(",",@_)
		# close
		.")";
	}

sub _slotp
	{
	# parsing part for slot
	my $self=shift;
	my %args=@_;
	my ($withNumber,$simpleSlot) = @args{'withNumber','simpleSlot'};
	
	my $candidate = $self->remainderHead;
	
	vverbose 2,"\tslotcontent ".$self->remainderHead."\n";
	return
	( 
		( $self->_token || ($withNumber && $self->_slotDigit) || $self->_twiddleSlot )
		|| ( 
			$self->syntaxException("Expected a slot-expression (token, {{\$token}}),"
				." found ".$candidate
				,$self->syntaxError)
			&& undef
			)
	)
	&&  ( 
		$self->sugar('\.',"Slot piece (.name)")
			? $simpleSlot
				? ($self->setSyntaxError("a simple slot (no dots)"))
				: $self->_slotp(%args,withNumber=>1) 
			: ( 
				$self->syntaxError(
					TemplateToPerl::SyntaxException->new(
						message=> "Expected a slot-expression (token, {{\$token}}),"
							." found ".$candidate,
						fileName => $self->provenance,
						line => $self->line, 
						characterPosition => $self->characterPosition,
						child => $self->syntaxError,
						)					
					)
				&& $self	# nb: provisional syntax error
				)
		)
	&& ((vverbose 2,"\t\tslot! next ",$self->remainderHead,"\n"),$self)
	;
	}

sub _slotDigit
	{
	my $self=shift;	
	my ($digits) = $self->pattern(qr/\d+/,'a .number');
	vverbose 2,"a digit before ".$self->remainder.": $digits ".(defined $digits ? "" : "null")."\n";
	return (defined $digits)
		? $self->appendParse($digits)
		: undef;	
	}

sub _token
	{
	my $self=shift;
	
	vverbose 2,"\ttoken ".$self->remainderHead,"\n";
	
	my ($token) = $self->pattern(qr/[[:alpha:]][[:alnum:]_]*/,'a token (alpha  alphanum)');
	return (defined $token)
		? $self->appendParse("'$token'")
		: undef;	
	
	}

	
##
# Tests
##

		
=test utilityFunctionSetup
	# This piece isn't a test, just subs. 
	
		#To handle the resulting perl code, so I can eval it
		sub perlismToText
			{	
			use Verbose; $kVerbose =$TemplateToPerl::Parse::kVerbose;
			$_[0] = join(",",@{$_[0]}) if (ref $_[0] eq 'ARRAY');
			
			# convert $self->interpolate... to a simple string
			vverbose 2,"unsimplified perl ".$_[0]."\n";
			$_[0] =~ s/\$self->_interpolate\(/_interpolate(/sg;
			$_[0] =~ s/\$self->_interpolateUrlEscaped\(/_interpolateUrlEscaped(/sg;
			$_[0] =~ s/\$self->_interpolateRaw\(/_interpolateRaw(/sg;
			$_[0] =~ s/\$self->_iterate\(/_iterate(/sg;
			vverbose 2,"simplified perl ".$_[0]."\n";
			
			my $expr = evalOrDieWithFixup( $_[0]); 
							
			return $expr;
			}
		sub evalOrDieWithFixup
			{
			# figure out current "eval" number
			eval 'die'; # must be a string!
			my ($num) = $@ =~ /\(eval (\d+)\)/;
			$num++;
			
			my $rez = eval $_[0];
			
			if ($@)
				{
				my $line = (caller(1))[2];
				my $file = (caller(1))[1];

				my $rep = "(text during $file at line $line)";

				$@ =~ s/\(eval $num\)/$rep/;
				die $@;
				}
				
			return $rez;
			}
		sub _interpolateUrlEscaped
			{
			my ($prov,$line,$expr,@slots) = @_;	
			return '({'.join('|',@slots).'})';
			}
		sub _interpolate
			{
			my ($prov,$line,$expr,@slots) = @_;	
			return '('.join('|',@slots).')';
			}
		sub _interpolateRaw
			{
			my ($prov,$line,$expr,@slots) = @_;	
			return '(['.join('|',@slots).'])';
			}
		
		sub _iterate
			{
			my ($prov,$line,$a,$b,$sub) = @_;
			return "(iterate $a $b (".(&$sub()).'))';
			}
		
		sub assertSyntaxError
			{
			my ($parser,$start, $errorRE, @message) = @_;
			
			assertDie(sub {$parser->${start}()},$errorRE,'Syntax Error ',@message);
			}

					
=test token
	Test simple case
		foreach my $string (qw(A bc a3 a3b a_b))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_token;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = $parser->result;
			assertEQ($rez->[0],"'$string'","Parsed '$string'");
			}
	
	Syntax error
		foreach my $string (('A#', 'b#c'))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_token;
			assertUndef($parser->syntaxError,"No syntax error yet '$string'") || next;
			assertEQ($parser->remainder,qr/^#/,"Stopped at pound '$string'")
			}
		
		foreach my $string ('_b', '3a3', '#a')
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_token;
			assertEQ($parser->syntaxError,qr/Expected a token.*$string/,"Syntax error '$string'");
			}
			
=test slot one element
	One element
		foreach my $string (qw(A bc a3 a3b))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_slot;
			my $rezlist = $parser->result;
			assertTest($rezlist || !$parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist);
			assertEQ(perlismToText($rez),"($string)","Parsed $string");
			}

=test slot syntax error
	Syntax error
		foreach my $string (qw(_b 3a3))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);

			assertSyntaxError($parser,'_slot',qr/Expected a slot-expression.*$string/,"Syntax error '$string'");
			}
			
=test slot path
	Multiple Elements
		foreach my $parts ((['a','b'], ['a','b','c'],['a',1,'b']))
			{
			my $string = join(".",@$parts);
			my $expected = "(".join("|", map {s/{{/(/g; s/}}/)/g; s/\$//g; $_} @$parts).")";
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_slot;
			my $rezlist = $parser->result;
			assertTest($rezlist || !$parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist);
			assertEQ(perlismToText($rez),$expected,"Parsed '$string'");
			}
		
	Syntax error
		foreach my $string (qw(6.t A.*.b A.[]))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_slot',qr/Expected a slot-expression/,"Syntax error '$string'");
			}
	
=test nested slot
	Nested twiddles in slot
		foreach my $parts (([qw({{$a}})], [qw({{$a}} b)], [qw(a {{$b}} c)], [qw({{$a}} {{$b}})]))
			{
			my $string = join(".",@$parts);
			my $expected = "(".join("|", map {s/{{/(/g; s/}}/)/g; s/\$//g; $_} @$parts).")";
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_slot;
			my $rezlist = $parser->result;
			assertTest($rezlist || !$parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist);
			# convert $self->interpolate... to a simple string
			my $expr=perlismToText($rez);
			assertEQ($expr,$expected,"Parsed '$string'");
			}
	
	Syntax Errors (no $)	
		foreach my $parts (([qw({{a}})], [qw({{a}} b)], [qw(a {{b}} c)]))
			{
			my $string = join(".",@$parts);
			my $expected = join(",", map {/^(\d+)$/ ? $1 : "'$_'"} @$parts);
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);

			assertSyntaxError($parser,'_slot',qr/Expected a slot-expression/,"Syntax error '$string'");
			}
	
	Syntax errors (no closing }})			
		foreach my $parts (([qw({{a)], [qw({{a b)], [qw(a {{b c)]))
			{
			my $string = join(".",@$parts);
			my $expected = join(",", map {/^(\d+)$/ ? $1 : "'$_'"} @$parts);
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);

			assertSyntaxError($parser,'_slot',qr/Expected a slot-expression/,"Syntax error '$string'");
			}
	
	Syntax errors (Only $)	
		foreach my $parts ((['{{IF $bob}}'], ['{{ITERATE $a $b}}', 'b']))
			{
			my $string = join(".",@$parts);
			my $expected = join(",", map {/^(\d+)$/ ? $1 : "'$_'"} @$parts);
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);

			assertSyntaxError($parser,'_slot',qr/Expected a slot-expression/,"Syntax error '$string'");
			}

=test twiddle slot
	Full {{}} around slot
		foreach my $string (qw({{$A}} {{$bc}} {{$a3}} {{$a3b}} {{$a.b}} {{$a.1.b}} {{$a.b.c}} {{$a.{{$b}}.c}}))
			{
			my $expected = join('|',split(/\./,$string));
			$expected =~ s/{{\$/(/g;
			$expected =~ s/}}/)/g;
			my $string2 = $string;
			#$string2 =~ s/{{\$//;
			
			my $parser = TemplateToPerl::Parse->new(string=>$string2);
			my $parsed = $parser->_twiddle;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string2'") || next;
			my $rez = join(".",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string2");
			}
	
	syntax error		
		foreach my $string (qw({{$}} {{$a.b.}} {{$a.{{}}.c}} ))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle',qr/Expected a slot-expression/,"'$string'");
			}

		foreach my $string (qw({{A}}))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle',qr/Expected a valid {{...}}/,"'$string'");
			}

		foreach my $string ('{{$a#1.b}}')
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle',
				[qr/Expected a closing }}/, qr/Expected a slot-expression/]
				,"'$string'");
			}
			
=test escaping
	Test URL and HTML escaping
		my %text =
			(
			'{{$a}}'=>'(a)',
			'{{$a.b}}'=>'(a|b)',
			'{{{$a}}}'=>'({a})',
			'{{{$a.{{$d}}.c}}}'=>'({a|(d)|c})',
			'{{{{$a.c}}}}' => '([a|c])',
			);
		while (my ($string,$expected) = each (%text))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_twiddle;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}
	
	Syntax errors
		my %errorText =
			(
			'{{{$a.{{{$d}}}.c}}}'=>[qr/Expected a valid {{...}}/,qr/char 9/],
			'{{{$a}}'=>[qr/Expected third }/,qr/char 6/],
			);
			
		while (my ($string,$error) = each (%errorText))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle'
				,$error
				,"Syntax error '$string'");
			}
						
=test iterate
	Basic Iterate
		my %text =
			(
			'{{ITERATE $a $b}}'=>'(iterate (a) b ())',
			'{{ITERATE $a.c $b}}'=>'(iterate (a|c) b ())',
			'{{ITERATE $a.{{$d}}.c $b}}'=>'(iterate (a|(d)|c) b ())',
			);
		while (my ($string,$expected) = each (%text))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_twiddle;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist).'})';
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}
			
	Syntax error
		my %errorText =
			(
			'{{ITERATE}}'=>'a valid {{...}}',
			'{{ITERATE }}'=>'collection',
			'{{ITERATE $a }}'=>'iterator',
			'{{ITERATE $a}}'=>'space',
			'{{ITERATE $a b}}'=>'iterator',
			'{{ITERATE a $b}}'=>'collection',
			'{{ITERATE $a $b.a}}'=>'a simple slot'
			);
			
		while (my ($string,$error) = each (%errorText))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle'
			,[qr/Expected a valid {{...}}/,qr/Expected $error /]
			,"Syntax error '$string'");
			}

=test close iterate
	Test /ITERATE
		my $string = '{{/ITERATE}}';
		my $expected = "})";
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_twiddle;
			my $rez = $parser->result->[-1];
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			assertEQ($rez,"$expected","Parsed $string");
			}

=test iterator compiles
		my $string = '{{ITERATE $a $b}}x{{$c}}{{/ITERATE}}';
		my $expected = "(iterate (a) b (x(c)))";
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->parse;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(".",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}
			
=test body
	HTML Body stuff
		foreach my $string 
			(
			'#hubert',
			'A b',
			"a b\nc d",
			"",
			"{",
			"'",
			"\\",
			'\\\'',
			)
			{
			my $expected = $string;
			
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->_body;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(",",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}
	
=test error location
	Test the location explanation
		my $string = "\n123{{A}}\n\n";
		my $parser = TemplateToPerl::Parse->new(string=>$string);
		$string =~ s/\n/\\n/sg;
		assertDie(sub{$parser->parse},qr/./,"Sanity '$string'") || return;
		assertEQ($parser->syntaxError->line,'2',"Syntax error '$string', check line #");
		assertEQ($parser->syntaxError->characterPosition,'4',"Syntax error '$string', check char #");
		assertToDo("try to get characterPosition to match earliest syntax-error");

=test if tag
	Basic if
		my %text =
			(
			'{{IF $a}}'=>'(a)',
			'{{IF $a.c}}'=>'(a|c)',
			'{{IF $a.{{$d}}.c}}'=>'(a|(d)|c)',
			'{{IF $a eq $a}}'=>'1',
			'{{IF $a eq $b}}'=>'',			
			'{{IF $a eq \'(a)\'}}'=>'1',
			'{{IF $a eq \'a\'}}'=>'',			
			);
		
		while (my ($string,$expected) = each (%text))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = assertNoDie(sub {$parser->_twiddle},"Parsed $string") || next;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rezlist = $parser->result;
			my $rez = join(",",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Evals $string");
			}
		
		
	Syntax error
		my %errorText =
			(
			'{{IF}}'=>'a valid {{...}}',
			'{{IF }}'=>'slot',
			'{{IF a}}'=>'slot',
			);
			
		while (my ($string,$error) = each (%errorText))
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			assertSyntaxError($parser,'_twiddle'
			,[qr/Expected a valid {{...}}/,qr/Expected $error /]
			,"Syntax error '$string'");
			}

=test close if
	Test /IF
		my $string = '{{/IF}}';
		my $expected = "2";
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			$parser->appendParse('1','2');
			
			my $parsed = $parser->_twiddle;
			my $rez = $parser->result->[-1];
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}

=test else clause
	the ELSE for an if
		my $string = "{{ELSE}}";
		my $expected = 	"";
		
		my $parser = TemplateToPerl::Parse->new(string=>$string);
		my $parsed = $parser->_twiddle;
		my $rez = $parser->result->[-1];
		assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
		assertEQ($rez,"$expected","Parsed $string");

=test else compiles
	IF and ELSE
		my %source = 
			(
			"{{IF \$a}}1{{ELSE}}2{{/IF}}" => '1',
			"{{IF !\$a}}1{{ELSE}}2{{/IF}}" => '2',
			);
		
		while (my ($string,$expected) = each %source)
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->parse;
			my $rez = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}	
	
=test if compiles
		my $string = '{{IF $a}}x{{$c}}{{/IF}}';
		my $expected = "x(c)";
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->parse;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(".",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}

		$string = '{{IF $a}}'."\n".'x{{$c}}'."\n".'{{/IF}}'."\n"; # extra eol!
		$expected = "\nx(c)\n\n";
			{
			my $parser = TemplateToPerl::Parse->new(string=>$string);
			my $parsed = $parser->parse;
			my $rezlist = $parser->result;
			assertUndef($parser->syntaxError,"No syntax error '$string'") || next;
			my $rez = join(".",@$rezlist);
			assertEQ(perlismToText($rez),"$expected","Parsed $string");
			}

=test comments
	Comments should be skipped: somewhat crude parsing (simple skip-to-end).
		my %source = 
			(
			'blah -->' => '',
			'blah -->a' => 'a',
			'blah <!-- -->' => '',
			'blah <!-- -->b' => 'b',
			'blah -> -->' => '',
			);
		
		# toEndOfComment
		while (my ($input,$expected) = each %source)
			{
			my $parser = TemplateToPerl::Parse->new(string=>$input);
			my $parsed = $parser->_toEndOfComment;
			assertUndef($parser->syntaxError,"No syntax error '$input'") || next;
			my $rezlist = $parser->result;
			my $rez = perlismToText( join(".",@$rezlist) ) . $parser->remainder;
			
			assertEQ($rez,
				$expected,
				"Rest of comment: $input");
			}
			
		# via parse
		my %beginComment = 
			(
			'<!--' => '',
			'a<!--' => 'a',
			'<!-- ' => '',
			'a<!-- ' => 'a',
			'a <!--' => 'a ',
			'<!-- x --><!-- ' => '',
			'j<!-- x -->k<!-- ' => 'jk',
			' j<!-- x -->k <!-- ' => ' jk ',
			'j <!-- x --> k<!-- ' => 'j  k',
			'{{$n}} <!-- {{$m}} ' => '(n) ',
			);
		while (my ($prefix,$expectedPre) = each %beginComment)
			{
			while (my ($postfix,$expectedPost) = each %source)
				{
				my $input = $prefix.$postfix;
				my $expected = $expectedPre.$expectedPost;
				
				my $parser = TemplateToPerl::Parse->new(string=>$input);
				my $parsed = $parser->parse;
				assertUndef($parser->syntaxError,"No syntax error '$input'") || next;
				my $rezlist = $parser->result;
				my $rez = perlismToText( join(".",@$rezlist) );

				assertEQ($rez,
					$expected,
					"Rest of comment: $input");
				}
			}
		
		# with trailing {{$x}}	
		while (my ($base,$baseExpected) = each %source)
			{
			my $input = "<!-- $base".'{{$f}}';
			my $expected = "$baseExpected(f)";
			
			my $parser = TemplateToPerl::Parse->new(string=>$input);
			my $parsed = $parser->parse;
			assertUndef($parser->syntaxError,"No syntax error '$input'") || next;
			my $rezlist = $parser->result;
			my $rez = perlismToText( join(".",@$rezlist) ) ;
			
			assertEQ($rez,
				$expected,
				"Rest of comment: $input");
			}
			

=cut

1;
