package Tests::Class::MethodMaker;

use IC::TestHarness;
use strict;

use Class::MethodMaker get_set=>[qw(prop)];

sub main
	{
	IC::TestHarness::Test
		(
			[qw(
			test
			)]
		);
	}
	
sub test
	{
	my $self=bless {},__PACKAGE__;
	
	$self->prop(45);
	logStatus($self->prop == 45,"Set");
	
	
	$self->prop(undef);
	logStatus(!defined $self->prop, "Set to undef");
	}

main();
