# Various exceptions, FILENAME != MODULE
use strict;
use warnings;
no warnings 'uninitialized';

package TemplateCompiler::Exception;
use base qw(Class::New);
use Class::MethodMaker [scalar =>[qw(message stackTrace)]];
use overload '""' => 'toString';

sub preInit
	{
	my $self=shift;
	$self->_stackTrace;
	return $self->SUPER::preInit(@_);
	}
	
sub toString
	{
	my $self=shift;
	return ref($self)." ".$self->_message;
	}

sub _message
	{
	# Construct the message without trying to cope with the getter/setter
	return shift->message;
	}
	
sub _stackTrace
	{
	use Carp;
	eval {confess};
	shift->stackTrace($@);
	}

sub findCaller
	{
	# Get the caller file/line outside this package
	# Good to figure out who gave us text to process (instead of file)
	
	my ($lastRelevantPackage, @aCaller);
	my $i=1;
	while ((@aCaller = caller($i))  && $aCaller[3])
		{
		my ($package, $filename, $line, $subroutine) = @aCaller;
		# would like to use __PACKAGE__ here, but it doesn't work
		$lastRelevantPackage = $i if ($subroutine =~ /^TemplateToPerl::/);
		#vverbose 0,$lastRelevantPackage," $i $package $subroutine $filename $line\n";
		$i++;
		#last if $i>15;
		}
	
	return "Can't determine call location" if ! $lastRelevantPackage;
	my @lastCaller = caller($lastRelevantPackage);
	
	return $lastCaller[1]." line ".$lastCaller[2];
	}
								
package TemplateCompiler::NewException;
use base qw(TemplateCompiler::Exception);
# new() was called with bad params

sub init
	{
	my $self = shift;
	
	use Carp;
	eval {confess};
	my $stackTrace = $@;
	$stackTrace =~ /::new\('TemplateCompiler::NewException'.+?\).+?at /m || warn "########fail $@";
	$stackTrace = $';
	$self->message( $self->message . " at $stackTrace");
	
	return $self->SUPER::init(@_);
	}
	
package TemplateCompiler::NoTemplateException;
use base qw(TemplateCompiler::Exception);

use Class::MethodMaker [scalar =>[qw(filename)]];
use overload '""' => 'toString';

sub _message
	{
	return "Template '".shift->filename."' doesn't exist";
	}
	
package TemplateCompiler::TemplateError;
use base qw(TemplateCompiler::Exception);

use Verbose;

use Class::MethodMaker [scalar => [
	{-default => [qw( line fileName characterPosition child )] },
	qw(-static canonicalFields)]];
use Class::MethodMaker [
	scalar => TemplateCompiler::TemplateError->canonicalFields,
	scalar => 'textCaller',
	];

sub init
	{
	my $self=shift;
	$self->textCaller( "from "
		.TemplateCompiler::Exception::findCaller) if !$self->fileName;
		
	return $self->SUPER::init(@_);
	}
	
sub _message
	{
	my $self=shift;
	
	return 
		$self->message." "
		.$self->_messageAt
		. ($self->child ? "\n\tbecause ".$self->child->toString : "\n")		
		;
	}

sub _messageAt
	{
	# the "at" part
	my $self=shift;
	
	return 
		($self->fileName || '(in text)')." "
		.($self->line ? "at line ".$self->line : "")." "
		.($self->characterPosition ? "at char ".$self->characterPosition : "")." "
		.($self->fileName ? "" : "(".$self->textCaller.")")
		;
	}
	
package TemplateCompiler::SyntaxException;
use base qw(TemplateCompiler::TemplateError);
# Syntax error in a tag

package TemplateCompiler::TagError;
use base qw(TemplateCompiler::TemplateError);
# new() only takes canonicalFields
# all other args are turned  into a join'd string as extraInfo
use Verbose;

use Class::MethodMaker [scalar => [
	{-default => [@{ TemplateCompiler::TemplateError->canonicalFields },
		qw(tag expression extraInfo )] },
	qw(-static canonicalFields)]];
use Class::MethodMaker [scalar => TemplateCompiler::TagError->canonicalFields ];

sub argInit
	{
	my $self=shift;
	my %args = @_;
	
	# Copy known args, removing from %args
	my %knownArgs;
	@knownArgs{ @{$self->canonicalFields} } = delete @args{ @{$self->canonicalFields} };
	
	$self->SUPER::argInit(%knownArgs);

	$self->extraInfo( $self->extraInfo . "," 
		.join(",", map {"$_ => ".$args{$_}} keys %args) 
		);
        return $self;
	}
	
sub _message
	{
	my $self=shift;
	return 
		'{{'.$self->tag." "
		.$self->expression.($self->extraInfo ? " (".$self->extraInfo.") " : "")
                .'}} '
		.$self->_messageAt 
		."\n"
		;
	}

package TemplateCompiler::TagNestingError;
use base qw(TemplateCompiler::TagError);

package TemplateCompiler::TagNotClosedError;
use base qw(TemplateCompiler::TagError);

package TemplateCompiler::ExtraCloseTagError;
use base qw(TemplateCompiler::TagError);

package TemplateCompiler::SlotException;
use base qw(TemplateCompiler::TemplateError);

use Class::MethodMaker [scalar => [qw(expression location)]];

sub _message
	{
	my $self=shift;
	
	return $self->message." in (".$self->expression.") "
	.$self->_messageAt;
	}

1;			
