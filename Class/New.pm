package Class::New;
# copyright 2002 Alan Grover (Ann Arbor, MI)
# Copyright Alan Grover 2005
# Licensed under the Perl Artistic License.

=pod

Ex:
	package MyClass;
	
	use Class::New;
	@ISA=qw(Class::New);
	
	...methods....
	
	
	
	package SomeOtherPackage;
	
	my $obj = MyClass->new();
	
A standard new() method for classes, with an init sequence.

Supports initializing from key=>value pairs in the new() call ("hash init").
Becomes $self->key(value). NB: Does not attempt to correct for the broken
Class::MethodMaker setters which ignore undef (thus, $self->key(undef) does
nothing). This class assumes you will use the fixed setters from Class::GetSet.

The initialization sequence for new() is:
	# standard 2 arg bless, supports inheritance
	# base type is a hashRef
	bless self into class
	
	# Set up default values (null arglist for new()).
	# Default implementation is nop.
	$self->preInit();
	
	# Treat @_ as a key=>value list 
	# and call setters like $self->key(value)
	# Assumes someone set up the setters (see Class::GetSet).
	# Override this if you don't want hash-style args for new().
	$self->argInit(@_);
	
	# Derive values, acquire resources, etc.
	# The object will have its properties by now, so you can
	# use them.
	# Default implementation is nop.
	$self->init();

Notes:
	Does not support
		$someObj->new();
	since I think that the intent is not obvious. See Class::Cloneable.
	
See Also
	Other Class::* for incremental additions to a New'able object, such as
	Cloneable, GetSet, Cached, etc.

Compatibility
	Compatible with Class::MethodMaker's getSet args. Obviously pointless to 
	use it's "new" with this.

Errors
	Class::New FATAL NoProto: Do not call new() on an object, only on a package/class (saw '$class')
		You attempted to call $someObject->new(). See note above.
	Class::New FATAL no such setter/method '$k' in class '$class'
		You attempted a new() with args, e.g. SomeClass->new(someKey=>someValue...)
		and "someKey" is not a setter/method in the object. 			
=cut

use strict;
use Carp;
use Verbose;
$kVerbose = 9;

sub new
	{
	my $class = shift;
	croak __PACKAGE__," FATAL NoProto: Do not call new() on an object, only on a package/class (saw '$class')" if ref $class;
	
	my $self = bless {},$class;
	
	$self->preInit();	
	$self->argInit(@_);
	$self->init();
	
	return $self;
	}

sub preInit {}
sub init {}

sub argInit
	{
	# treat new's args as key=>value for init
	my $self=shift;
	
	#vverbose 0,"$self keys=",(scalar @_)/2,"\n";
	
	my ($k,$v);
	# go through by 2's to get key=>value
	for (my $i=1;$i<=$#_; $i+=2)
		{
		($k, $v) = @_[$i-1,$i];
		
		# NB: The line spacing here is special.
		# NB: The eval must be exactly the 3rd line up from the __LINE__ assignment.
		# NB: This lets us detect method-not-found errors
		eval {$self->$k($v)};
		if ($@)
			{
			my $l=__LINE__ - 3;
			my $err=$@;
			my ($eline) = $err =~ /line (\d+)\./;
			
			if ($err =~ m|at [^ ]*/?Class/New.pm| && $eline == $l && $err =~ /Can't locate object method "$k"/)
				{
				croak __PACKAGE__," FATAL no such setter/method '$k' in class '",ref $self,"'";
				}
			die "'$eline' $err";
			}
		}
	}

=head1 diff($other)

Try to identify any differences between $self and $other, return as a list
 of messages.

This implementation doesn't actually diff much.

#This implementation only checks the keys=>values if $self is a hashref. Will 
#recurse if the value->can('diff');

=cut

sub diff
	{
	# $indent is the current indent level for recursing
	my $self=shift;
	my ($other, $indent)=@_;
	
	my @problems;
	
	my $tabs = "\t" x $indent;
	
	if (!ref $other)
		{
		push @problems, "${tabs}Other ('$other') wasn't a ref (probably not an object)";
		return \@problems;	
		}
	
	my $class=ref $self;
	
	if ($class ne ref $other)
		{
		push @problems, "${tabs}Other ('$other') isn't same class ($class)";
		return \@problems;	
		}
	
	return \@problems;
	}

=head1 isCloneable()

Just a convenience method to test if we're a cloneable or not.  We
assume we are not, by default.

Cloneable means that
	my $cloned = $original->new();
will result in $cloned being equivalent to $original, i.e., a copy.
We make no claims about it being deep/shallow clone.

=cut

sub isCloneable { 0 }

1;
