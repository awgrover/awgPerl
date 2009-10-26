package Class::GetSet;
# copyright 2002 Alan Grover (Ann Arbor, MI)

=pod

A critique of Class::MethodMaker.

Example:
	package MyClass;
	use Class::GetSet qw(a b c);
	
	blah.....
		my $getTheValue = $self->a();
		
		$self->a($setTheValue);	# works with undef
	

Use:
	use Class::GetSet qw(prop1 prop2 prop3 ...);
Creates getter/setters. Equivalent to:
	use Class::GetSet GetSet=>[qw(prop1 prop3 prop3 ... );

You can create a named set of getter/setters
	use Class::GetSet setName1=>[qw(prop1 prop3 prop3 ... )];
which creates a property that returns the list of getter/setter names, e.g.
$object->setName1() returns ('prop1', 'prop2', 'prop3', ... ).

Easily add getter/setters to your class. This module does nothing else 
and is an implicit criticism of Class::MethodMaker in that regard. More
explicitly, Class::MethodMaker creates setters that ignore undef (e.g.
$object->someSetter(undef) ), which has always pissed me off. Oh, he
fixed that ... that's going to break some code that relies on the
broken behavior.

Note that the getter/setters take and return scalars only. So, if you
want array/hashes/etc., set and get references. Another implicit
criticism, though I had colleagues who used the non-scalar getter/setters.

Note that the getter/setters do NOT store their values under keys in the
object (assuming it is a hash). This uses closures, which also means you
wouldn't be able to discover the getter/setters by introspection. That
would annoy me, so you can get the complete list of getter/setters via
the auto-generated groupname property GetSet, thus: $object->GetSet().

Note, that since this doesn't assume the object is a blessed hash, this
will work with any blessed ref.

Since the getter/Setters are generated at "use" time (i.e. BEGIN block time, 
i.e. compile time), and are subroutines (methods), you may override them by
declaring a "sub" of the same name. Declare it lexically later, or in a 
subclass.

=cut


1;
