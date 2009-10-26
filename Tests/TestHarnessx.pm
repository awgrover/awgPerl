package Tests::TestHarnessx;
use Class::New;
@ISA=qw(Class::New);

use TestHarness;

use vars qw($gInit);
$gInit = 0;

END
	{
	die "didn't call new" if $gInit != 1;
	}

sub init
	{
	# called by new(), to test for new() being called
	$gInit = 1;
	}

sub test_success
	{
	logStatus(1,"Succeed") || die "didn't return true from logstatus";
	logStatus(1,"Succeed"," multi args");
	}

sub test_fail
	{
	logStatus(0,"Fail") && die "didn't return false from logStatus";
	logStatus(0,"Fail"," multi args");
	}

sub test_die
	{
	shouldDie();
	logStatus(0,"Should have died");
	}
1;
