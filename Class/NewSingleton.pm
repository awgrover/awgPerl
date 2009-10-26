package Class::NewSingleton;
use base 'Class::New';

use strict;
use warnings;

our %gSingletons;

sub new 
	{
	my $self=shift;
	my $class = ref($self) || $self;
	return $gSingletons{$class} || ($gSingletons{$class} = $self->SUPER::new(@_) );
	}

1;			
