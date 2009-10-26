package DocumentParser;
use base qw(Class::New);
# Copyright Alan Grover 2005
# Licensed under the Perl Artistic License.

use strict;
use warnings;
no warnings 'uninitialized';

use Carp qw(croak confess);
sub debug {} #{print STDERR @_; if ($_[-1] !~ /\n$/s) {print STDERR " at ".(caller)[1]," line ",(caller)[2],"\n"}}

use Class::MethodMaker [scalar => [qw(_sequence _inputCache _PushBack)] ];

sub Cleanup {};

# "static" properties, in the $self class
sub rulesParser
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::rulesParser"} = $_[0] : ${$class."::rulesParser"};
	use strict 'refs';
	}

sub _globalAccumulators
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::_globalAccumulators"} = $_[0] : ${$class."::_globalAccumulators"};
	use strict 'refs';
	}

sub _globalBeforeRules
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::_globalBeforeRules"} = $_[0] : ${$class."::_globalBeforeRules"};
	use strict 'refs';
	}

sub _globalEndRules
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::_globalEndRules"} = $_[0] : ${$class."::_globalEndRules"};
	use strict 'refs';
	}

sub _ruleSequence
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::_ruleSequence"} = $_[0] : ${$class."::_ruleSequence"};
	use strict 'refs';
	}

sub _rules
	{
	my $class=ref shift;
	no strict 'refs';
	return scalar (@_) ?  ${$class."::_rules"} = $_[0] : ${$class."::_rules"};
	use strict 'refs';
	}

sub preInit
	{
	my $self=shift;
	debug "# $ARGV";
	$self->_rules({}) if !$self->_rules;
	$self->_ruleSequence([]) if !$self->_ruleSequence;
	$self->_globalEndRules([]) if !$self->_globalEndRules;
	$self->_globalBeforeRules([]) if !$self->_globalBeforeRules;
	$self->_globalAccumulators([]) if !$self->_globalAccumulators;
	$self->_PushBack(undef);
	$self->_inputCache({});
	$self->reset;
	}

sub reset
	{
	my $self=shift;
	$self->_sequence(0);
	foreach (keys %{$self->_inputCache}) {delete $self->_inputCache->{$_}};
	$self->_inputCache({});
	foreach my $ga (@{$self->_globalAccumulators})
		{
		my ($globalAccumulatorRule,$text,$accumulator) = @$ga{'rule','text','accumulator'};
		@$accumulator = ();
		}
	}

sub init
	{
	my $self=shift;
	eval "use ".$self->GrammerCompiler.";";
	die $@ if $@;
	$self->rulesParser($self->GrammerCompiler->new) if !$self->rulesParser;
	}
	
#############

sub Build
	{
	my $self=shift;

	# only build once per class
	if (scalar @{$self->_ruleSequence})
		{
		$self->reset;
		foreach my $rule (values(%{$self->_rules}), map {$_->{'rule'}} @{$self->_globalAccumulators})
			{
			debug "reset ".$rule->name." ($rule)";
			next if !UNIVERSAL::isa($rule,'UNIVERSAL');
			$rule->reset($self);
			}
		return $self;
		}

	# Turn rules into objects
	my $rules = $self->inputLooksLike;
	die "inputLooksLike() should return a hash, found $rules" 
		if !ref($rules) || ref($rules) ne 'HASH';
	my $rulePart = $rules->{'rules'};

	die "No 'rules=>...' found" if !$rulePart;
	die "'rules' part not in pairs" if scalar(@$rulePart) % 2;
	debug "Rules ",scalar(@$rulePart)/2;

	my %globalAccumulators;

	my $ruleCount = scalar(@$rulePart)/2;
	my $sequence = 0;
	for (my $i=0;$i<scalar(@$rulePart);$i +=2)
		{
		my ($rule);
		my ($ruleName,$definition) = ($rulePart->[$i],$rulePart->[$i+1]);
		next if !$ruleName;
		if ($ruleName eq '&&')
			{
			($rule,$ruleName) = $self->makeSlaves($sequence,$definition);
			}
		elsif ($ruleName eq '*')
			{
			debug "\tGlobal(*) $sequence ($i out of ".scalar(@$rulePart)."), ".$definition->[0]."...";
			%globalAccumulators = (%globalAccumulators, @$definition); # a hash "push", inefficient
			# "Skip", i.e. don't treat like a regular rule
			next;
			}
		else
			{
			debug "\t$sequence $ruleName=>$definition";
			$rule = Rule->new(name=>$ruleName, parser=>$self
				, sequence=>$sequence, decodeDefinition=>$definition, );
			}
		confess "INTERNAL: no rulename (rule= $rule)" if !$ruleName;
		push @{$self->_ruleSequence}, $ruleName;
		$self->_rules->{$ruleName} = $rule;
		$sequence++;
		}

	my $closureRuleCount= $sequence; # need copy for closure
	my $eofDefinition = sub 
		{
		die "WARN EOF seen too soon during ",ref($self)," ".$self->_ruleSequence->[$self->_sequence]."(#".$self->_sequence.") $ARGV" 
			if eof(ARGV) && $self->_sequence < $closureRuleCount;
		};
	# active up to last rule
	push @{$self->_globalEndRules}, {sequence=>$closureRuleCount-1,rule=>undef, definition=>$eofDefinition, text=>"(EOF detector)"};

	$self->setupGlobalAccumulators($self->sequence2Rule(-1),$sequence,\%globalAccumulators);

	$self->postBuild;
	debug "End Rules";

	return $self;
	}

sub setupGlobalAccumulators
	{
	my $self=shift;
	my ($lastRule,$nextSequence,$accumulators) = @_;

	return if !scalar(keys %$accumulators);
	debug "\t>>Setup accumulators ",scalar(keys %$accumulators);

	while (my ($ruleName,$definition) = each %$accumulators)
		{
		debug "\tAccum: $ruleName";
		# add as dependency on last rule (set rule->seq = last)
		# but don't push on list (cf. slaves)
		my $rule = Rule->new(name=>$ruleName, parser=>$self
			, sequence=>$nextSequence-1, decodeDefinition=>$definition,
			_isSlave=>1);

		# Do allow use by Element()
 		$self->_rules->{$ruleName} = $rule;

		# add as a _globalAccumulator in loop (before rule): rule && accumulate && return 0
		push @{$self->_globalAccumulators}, {rule=>$rule, text=>"global $ruleName", accumulator=>[]};
		}
	push @{$lastRule->_slaves}, GlobalAccumulatorSlave->new(name => 'GlobalAccumulatorSlave', parser => $self);
	}
	
sub globalAccumulatorSlaveHook
	{
	# Called by the exited() of the globalAccumulatorSlave we added to the last rule
	# Needed to set the _inputCache, so that our hacked slave-dependency works
	my $self=shift;
	
	foreach my $ga (@{$self->_globalAccumulators})
		{
		my ($rule,$accumulator) = @$ga{'rule','accumulator'};
		debug "Copy ",$rule->name;
		$self->_inputCache->{$rule->name} = join(" ",@$accumulator);
		}
	}
	
sub postBuild {}

sub makeSlaves
	{
	my $self=shift;

	my ($sequence,$definitions) =@_;

	die "Rule #$sequence should have at least 2 parts, found".scalar(@$definitions) 
		if scalar (@$definitions) < 2;
	die "Rule #$sequence should have pairs" 
		if scalar (@$definitions) % 2;

	# First rule is master, and is _at_ the sequence-number
	my ($firstRuleName,$firstDefinition) = ($definitions->[0],$definitions->[1]);
	my $firstRule = Rule->new(name=>$firstRuleName, parser=>$self
		, sequence=>$sequence, decodeDefinition=>$firstDefinition);

	# The slaves _have_ the same sequence number
	for (my $i=2;$i<scalar(@$definitions);$i +=2)
		{
		my ($ruleName,$definition) = ($definitions->[$i],$definitions->[$i+1]);
		debug "\t\tslave rule $ruleName=>$definition";
		my $rule = Rule->new(name=>$ruleName, parser=>$self
			, sequence=>$sequence, decodeDefinition=>$definition
			,_isSlave=>1);

		push @{$firstRule->_slaves} , $rule ;
		confess "INTERNAL: no rulename (rule= $rule)" if !$ruleName;
 		$self->_rules->{$ruleName} = $rule;
		}
	return ($firstRule,$firstRuleName);
	}

sub globalRule
	{
	my $self=shift;
	my ($ruleList, $msg) = @_;

	my $i=0;
	foreach my $aGlobal (@$ruleList)
		{
		my ($fn, $nextRule, $sequence, $text) = @$aGlobal{qw(definition rule sequence text)};
		die "Bolixed: ${msg}"."[$i] from rule $sequence is not a function, it's '$fn'" 
			if ref($fn) ne 'CODE';

		debug "\t@".$self->_sequence," global $msg $sequence $text";
		if ($sequence > $self->_sequence)
			{
			debug "\t\tcheck $msg #$sequence $nextRule $text";
			my ($hit) = $self->$fn();
			if ($hit)
				{
				debug "\t\t\thit $msg $nextRule #$sequence during ".$self->_sequence;
				return ref($nextRule) ? $nextRule : $self->sequence2Rule($nextRule);
				}
			}
		$i++;
		}
	debug "\t\tnot $msg";
	return undef;
	}

sub Element
	{
	my $self = shift;
	my ($ruleName) = @_;

	#debug "\t\tcache $ruleName=".$self->_inputCache;
	return $self->_inputCache->{$ruleName} if exists $self->_inputCache->{$ruleName};
	# FIXME: $self->fn is bad? no dependencies, can't be a slave
	if ($self->can($ruleName))
		{
		debug "try $. '$ruleName()' '$self'" ;
		return $self->_inputCache->{$ruleName} = $self->$ruleName();
		}

	croak "Didn't find a parse rule '$ruleName' in ".ref($self) if !exists $self->_rules->{$ruleName};
	my $rule = $self->_rules->{$ruleName};

	debug "try $. '$ruleName' '$self' (slave? ".$rule->_isSlave.")";

	my $ruleSequence = $rule->sequence;

	# Deal with a slave
	if ($rule->_isSlave)
		{
		# sequence is really the master, which will run us
		debug "\tcall master ".$self->_ruleSequence->[$ruleSequence];
		$self->Element($self->_ruleSequence->[$ruleSequence]);
		debug "\tmaster done, we ($ruleName) should be in cache";
		return $self->Element($ruleName);
		}

	# Run earlier rules
	if ($self->_sequence < $ruleSequence)
		{
		debug "Out of sequence $ruleName=$ruleSequence (seq=".$self->_sequence.")";
		$self->Element($self->_ruleSequence->[$ruleSequence-1]);
		# Earlier rules may have skipped ahead, so just retry ourself
		return $self->Element($ruleName);
		}

	debug "\tstart of ",$self->_ruleSequence->[$self->_sequence]," seq ".$self->_sequence;
	my ($rez, $continue, $accumulator, $skipToRule);
	while (defined($self->bufferedNextLine) && ! ($skipToRule = $self->globalRule($self->_globalBeforeRules,'before')) )
		{
		debug ("$.(".$self->documentLineNumber.") $_");
		
		# do ends-before
		if ($rule->endsBefore(\$accumulator))
			{
			$rez = '';
			$self->pushBack;
			last;
			}

		# Do accumulators
		foreach my $ga (@{$self->_globalAccumulators})
			{
			my ($globalAccumulatorRule,$text, $gaAccum) = @$ga{'rule','text','accumulator'};
			debug "\t>>Accumulator ".$globalAccumulatorRule->name;
			my ($gaRez,$gaContinue) = $globalAccumulatorRule->runDefinition();
			if (defined $gaRez)
				{
				debug "\t\t# got $gaRez";
				push @$gaAccum, $gaRez;
				# we never call ->exited on a globalAccumulator
				}
			debug "\t\t<<Accumulator";
			}

		# should we accumulate rez?
		($rez,$continue) = $rule->runDefinition(\$accumulator);
		
		debug "$ruleName failed $." if !defined $rez;
		last if !defined $rez;
		
		# FIXME: filters go here, f($rez), again, return undef(no chg) or changed

		# check end rules, capture skipTo
		# Don't check if we haven't consumed this line
		if (!defined $self->_PushBack)
			{
			$skipToRule = $self->globalRule($self->_globalEndRules,'after');
			last if $skipToRule;
			debug "\tDone with global after";

			my $ends = $rule->endsAfter(\$accumulator);
			last if $ends;
			debug "\tDone with local after";
			}

		debug "\t\t! continue" if !$continue;
		last if !$continue;
		$rez = undef; # mostly for pushback off end when a before rule
		debug "\t(again) $continue";
		};
	# FIXME: this is bad? it only pushbacks one $_, even if a series of lines has been read
	$self->pushBack if ! defined $rez;

	debug "\tend of ",$self->_ruleSequence->[$self->_sequence]," skipTo? $skipToRule, pushback'd? ",defined($rez),", no more? ",defined ($rez) ? !defined ($self->_PushBack) : !defined ($_);
	my $nextSequence = $skipToRule ? $skipToRule->sequence : $ruleSequence+1;
	
	# If we skipped any rules, set their result to ''
	foreach (my $i = $self->_sequence +1; $i <= $nextSequence -1; $i++)
		{
		my $skipRuleName = $self->_ruleSequence->[$i];
		$self->_rules->{$skipRuleName}->exited('');
		debug "\t\t\tcache=".$self->_inputCache;
		}
	$self->_sequence($skipToRule ? $skipToRule->sequence : $ruleSequence+1);

	debug "\t\texiting $ruleName:".substr($accumulator,0,20);
	return $rule->exited($accumulator);	# mostly to mark slaves as done, and cache result
	}

sub sequence2Rule
	{
	my $self = shift;
	my ($i) = @_;
	return $self->_rules->{$self->_ruleSequence->[$i]};
	}

sub pushBack
	{
	shift->_PushBack($_);
	}

sub bufferedNextLine
	{
	my $self = shift;
	if (defined $self->_PushBack)
		{
		$_ = $self->_PushBack;
		$self->_PushBack(undef);
		return $_;
		}
	return $self->nextLine;
	}
	
package Rule;
use base qw(Class::New);

use Carp;

use Class::MethodMaker [scalar => [qw(name parser sequence _definitions _endsBefore _endsAfter _slaves _isSlave)] ];

our @gWarnings;

use overload '""' => 'toString';

sub debug;
*debug=*DocumentParser::debug;

sub reset
	{
	my $self=shift;
	my ($parser) = @_;
	$self->parser($parser);
	foreach (@{$self->_slaves})
		{
		$_->reset(@_);
		}
	}

sub toString
	{
	my $self=shift;
	return "<".overload::StrVal($self).": ".$self->name." @".$self->sequence.">";
	}
	
sub preInit
	{
	my $self=shift;
	$self->_definitions([]);
	$self->_endsBefore([]);
	$self->_endsAfter([]);
	$self->_slaves([]);
	}

sub decodeDefinition
	{
	my $self=shift;
	my ($defString) = @_;

	# Turn definition into a fn

	my $definition;
	# FIXME: special case a bare regex until better parsing
	if (ref($defString) eq 'Regexp')
		{
		$definition = [ [ Regexp=>$defString ] ]
		}
	else
		{
		confess "Expected a string to parse, found $defString" if ref $defString;
		defined($definition = $self->parser->rulesParser->definitionList($defString)  )
			|| die "Syntax Error $defString: ",$self->parser->rulesParser->error();
		if (! ref $definition)
			{
			die "bad definition #0 '$definition' in ",$self->name;
			}
		}

	if (ref($definition) eq 'ARRAY')
		{
		debug "\t".$self->name." is list...";
		my $i=0;
		foreach my $oneDef (@$definition)
			{
			$i++;

			#if (!ref $oneDef) { die "bad definition #$i '$definition' (got '$oneDef') in ",$self->name }

			# should be makeDefinition_$key($value)
			if (ref $oneDef eq 'ARRAY')
				{
				push @{$self->_definitions},$self->makeDefinition($i,$oneDef);
				}
			else
				{
				die $self->name." definition $i is not an array ($oneDef)";
				}
			}
		}
	else
		{
		die "Unknown definition type: $definition in ".$self->name;
		}
	}

sub makeDefinition
	{
	# The factory:
	# (makeDefinition_<name>, $value) turned into parser
	my $self=shift;
	my ($defNum,$pair,$message) = @_;
	my ($defType,$defValue) = @$pair;

	debug "\t",$self->name." definition $defNum ($defType=>$defValue)";

	my $fnName = 'makeDefinition_'.$defType;
	die $self->name." definition $defNum, No way to $fnName" if !$self->can($fnName);

	return $self->$fnName($defNum,$defValue,$message);
	}

sub makeDefinition_skipAfter
	{
	my $self=shift;
	my ($defNum,$value) = @_;
	
	debug "\t",$self->name." definition $defNum, $value is a skipAfter global, at seq ".$self->sequence;

	my $fn = $self->makeDefinition($defNum,$value,"\tskipAfter ");
	my $nextRule = $self->sequence+1;
	debug "\t\twill skip to $nextRule";
	push @{$self->parser->_globalEndRules}, {sequence=>$self->sequence,rule=>$nextRule, definition=>$fn, text=>$value->[1]};
	return ();
	}

sub makeDefinition_endsBefore
	{
	# Check this type before "regular" rules
	my $self=shift;
	my ($defNum,$value) = @_;

	debug "\t",$self->name." $value is a endsBefore";

	my $fn = $self->makeDefinition($defNum,$value,"\tendsBefore ");
	push @{$self->_endsBefore}, $fn;
	return ();
	}

sub makeDefinition_startsAt
	{
	my $self=shift;
	my ($defNum,$value) = @_;

	debug "\t",$self->name." $value is a startsAt global, at seq ".$self->sequence;

	my $fn = $self->makeDefinition($defNum,$value,"\tstartsAt ");
	push @{$self->parser->_globalBeforeRules}, {sequence=>$self->sequence,rule=>$self, definition=>$fn, text=>$value->[1]};
	return ();
	}
	
sub makeDefinition_startsAfter
	{
	my $self=shift;
	my ($defNum,$value) = @_;

	debug "\t",$self->name." $value is a startsAfter global, at seq ".$self->sequence;

	my $fn = $self->makeDefinition($defNum,$value,"\tstartsAfter ");
	push @{$self->parser->_globalEndRules}, {sequence=>$self->sequence,rule=>$self, definition=>$fn, text=>$value->[1]};
	return ();
	}

sub makeDefinition_Regexp
	{
	my $self=shift;
	my ($defNum,$value,$msg) = @_;
	return sub {debug "\t\t$msg".$self->name," $value"; if (/$value/) {$1 || $_} else {undef}};
	}
	
sub makeDefinition_fn
	{
	my $self=shift;
	my ($defNum,$value,$msg) = @_;

	die $self->name." '$value' not a string (to be a fn) ",join(",",@$value) if ref $value;
	debug "\t",$self->name." '$value' is a fn/subrule";
	if ($self->parser->can($value))
		{
		return sub {debug "\t\t$msg".$self->name," $value"; shift->$value()};
		}
	else
		{
		die $self->name," No such subrule: '$value' in ".$self->name;
		}
	}

sub makeDefinition_expression
	{
	# An expression can return 1 value: true/false (for things like 'ends after')
	# or standard 2 values: (undef/result, continue)
	my $self=shift;
	my ($defNum, $value,$msg) = @_;

	my $sub = 'sub 
		{
		debug "\t\t$msg".$self->name." expression ($value)";
		my @rez = do '.$value.';
		return (scalar(@rez)>1) ? @rez : ($rez[0] ? $_ : undef, 0);
		}';
	debug "\t".$self->name." definition is expr: $sub";
	my $fn = eval $sub;
	die $self->name." definition $@" if $@;
	return $fn;
	}
	
sub endsBefore { return shift->ends('_endsBefore',@_); }
sub endsAfter { return shift->ends('_endsAfter',@_); }

sub ends
	{
	# return true if any of the definitions in the list is true
	# : _endsBefore, _endsAfter
	my $self=shift;
	my $listName = shift;
	
	debug "\t\t$listName..." if scalar(@{$self->$listName()});
	my $i=1;
	foreach my $def (@{$self->$listName()})
		{
		# run as if part of the parser
		my ($rez,$continue) = $self->parser->$def(@_);

		if (defined $rez) 
			{
			debug "\t\t\t$listName ($rez)!";
			return 1;
			}
		$i++;
		}
	return 0;
	}

sub runDefinition
	{
	# see if our definition indicates continue, finish, or fail
	# definitions should return (matched-value,continue), and continue defaults to 0
	# finish: (!undef) || (!undef,0)
	# fail: (undef)
	# continue: (!undef,1);
	my $self=shift;
	my ($refAccumulator,$dontAccumulate) = @_;

	my ($rez,$continue);
	foreach my $def (@{$self->_definitions})
		{
		($rez,$continue) = $self->parser->$def($refAccumulator);
		if (!defined $rez)
			{
			debug "\t\t\tfailed";
			return ($rez,$continue);
			}
		};
	debug "\t\tdefinitions passed";
	$$refAccumulator .= $rez unless $dontAccumulate;

	debug "\t\tSlaves ..." if scalar(@{$self->_slaves});
	foreach my $slave (@{$self->_slaves})
		{
		debug "\t\t\tslave ".$slave->name."... "
			,(
				(exists $self->parser->_inputCache->{$slave->name})
				? 'already cached'
				: 'not cached yet'
			);
		if (!exists $self->parser->_inputCache->{$slave->name})
			{
			debug "\t\tSlave:".$slave->name;
			my ($slaveRez) = $slave->runDefinition($refAccumulator,1);
			if (defined $slaveRez)
				{
				debug "\t\t\tslave->$slaveRez";
				$slave->exited($slaveRez);
				}
			}
		}
		
	debug "\t\t\t->'$rez";
	return ($rez,$continue);
	}

sub exited
	{
	# Called when the rule has finished/failed
	my $self=shift;
	my ($value) = @_;

	foreach my $slave (@{$self->_slaves})
		{
		confess "INTERNAL, ${self}->_slaves has not-an-object '$slave'" if ! UNIVERSAL::isa( $slave, 'UNIVERSAL');
		debug "\t\tmark slave ".$slave->name." as exited...";
		if (!exists $self->parser->_inputCache->{$slave->name})
			{
			my $dumyValue = '';
			$slave->exited($dumyValue); # since "we" can modify value via Cleanup()
			}
		}
	#debug "\t\tcached (".$self->parser->_inputCache.") ".$self->name."'",substr($value,0,40)."...";

	# Allow global post-filtering (FIXME: bad name)
	$self->parser->Cleanup(\$value);

	return $self->parser->_inputCache->{$self->name} = $value;
	}

####
package GlobalAccumulatorSlave;
# A hack to copy globalAccumulator values to inputCache at done
use base qw(Rule);

sub runDefinition {(undef,0)}

sub exited
	{
	my $self=shift;
	# Do not call SUPER, because we don't have a real name, we are fake

	$self->parser->globalAccumulatorSlaveHook;
	return undef;
	}

END 
	{
	 if (scalar @gWarnings)
	 	{
		print STDERR "## Warnings\n";
		print STDERR @gWarnings
		}
	}


1;
