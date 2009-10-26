package Blemish::Rule::Echo;
use Class::New;
@ISA=qw(Class::New);

use warnings;
use strict;

sub preInit
	{
	my $self=shift;
	$self->{'info'} = [];
	}

=h1 message => <some message>

Print the message

=cut

sub message
	{
	my $self= shift;
	if (scalar @_)
		{
		($self->{'messsage'}) = @_;
		}
	else
		{
		return $self->{'messsage'};
		}
	}
	
sub build
	{
	my $self=shift;
	
	print STDERR $self->message,"\n";
	return [];
	}

1;
