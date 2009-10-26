package Verbose::Default;
# copyright 2002 Alan Grover (Ann Arbor, MI)

use strict;

sub vverbose
	{
	my $targetClass=shift;
	my ($method, $line) = (shift, shift);
	
	# Always 2 up
        my $final = pop @_;
        chomp $final;
	print STDERR "[$method.$line] ".join("",@_).$final."\n";
	}
	
1;
