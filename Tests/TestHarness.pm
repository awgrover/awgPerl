# run via ./testharness

package Tests::TestHarness;

use TestHarness;

use vars qw($gHit);
$gHit = "";

END
	{
	die "didn't run the test routine '$gHit'" if $gHit ne '01';
	#print "Ran test routine\n";
	}
	
sub test_1setSomething
	{
	$gHit .= "1";
	}

sub test_0setSomething
	{
	$gHit .= "0";
	}

	
1;
