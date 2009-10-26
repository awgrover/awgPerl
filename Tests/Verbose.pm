package Tests::Verbose;

use strict;

use Verbose;

$kVerbose = 4;

sub main
	{
	verbose "Verbosed\n";
	vverbose 4,"VVerbosed\n";
	vverbose 5,"Shouldn't verbose\n";
	
	Tests::Verbose::otherPkg::tryIt();
	print "That was 4 of 'em\n";
	print "$kVerbose == 4\n"; die "bad bad" if $kVerbose != 4;
	print "No more verboses\n";
	Tests::Verbose::otherPkg2::tryIt();
	
	}



package Tests::Verbose::otherPkg;


use Verbose;

$kVerbose = 5;

sub tryIt
	{
	verbose "Should verbose\n";
	vverbose 5,"Should verbose\n";
	vverbose 6,"Shouldn't verbose\n";

	}

package Tests::Verbose::otherPkg2;


use Verbose 'Off';

$kVerbose = 5;

sub tryIt
	{
	vverbose 0,"Shouldn't verbose\n";
	verbose "Shouldn't verbose\n";
	vverbose 5,"Should verbose\n";
	vverbose 6,"Shouldn't verbose\n";

	}

Tests::Verbose::main();
1;
