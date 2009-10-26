package TestHarness;
use Class::New;
@ISA=qw(Class::New);

=pod

Run the tests in a package (or set of packages).

Example
	package Tests::myTestPackage;
	
	use TestHarness;	# access to logStatus()
	
	# Tests, in lexical order
	
	use TestHarness someTestName=>sub 
		{
		logStatus(1==1,"one should equal one");
		}
	
	...
	
	# or Tests in sorted order
	
	sub test_someTestName
		{
		logStatus(-f ".","The current directory exists");
		}

	% perltest myTestPackage
	
	# the output will be a list of successes, followed by failures.

package	Tests::yourTestPackage;
	You need to put things in a package so TestHarness has a namespace to
	hunt through. I recommend putting tests in a separate file, in a separate tree, with the
	root as Tests. Thus, "Tests::YourPackage". Otherwise, I'd suggest
	suffixing "_Tests": "YourPackage_Tests" (thus making it easy to skip
	test packages when installing, etc.). Putting the tests in Tests:: makes
	it easier for everyone to skip the files if they want, without having to
	special case your naming convention. I suppose some autosplit protocol
	might work too.
	
use TestHarnes;	
	You need the "use" so you can use logStatus().

use TestHarness someTestName=>sub {...}
	The "use" with arguments accumulates subroutines, in order, for the 
	TestHarness to run.

sub test_someTestName
	Otherwise, TestHarness collects the "text_xxx" routines, and runs 
	them in sort order.

new()
	If the package is a class (i.e. has a new() method), 
	TestHarness will new() it, then run the tests as methods.

logStatus(boolean,message)
	This is like an assert: the boolean should be true, and the message 
	explains the expected state. I often add some conditional expressions 
	to show the value when the boolean is false.
	
	Note that the report will refer to routines of the form test_xxx() rather
	than where you called logStatus().

% testHarness somePackage
	Run the testHarness command from the command line, 
	give it a package name.

TestHarness->new("somePackage")->main();
	Runs the tests on the package. See the TestHarness command for convenience.

TestHarness::report()
	Generates a report. Cumulative over all ->main()'s.
	
=cut

use strict;
use warnings;
use Carp;

use awgrover::Report;
use Verbose; # 'Off';
$kVerbose = 0;

use vars qw(%gStatus $gCountTests $gLastTarget %gStatusNames);
%gStatus = ();
$gCountTests = 0;

use Class::MethodMaker get_set=>[qw(targetPackage testRoutines packagesAtCheckPoint)];

sub argInit
	{
	my $self=shift;
	my ($targetPackage) = @_;
	$self->targetPackage($targetPackage);
	vverbose 2,"target=$targetPackage\n";
	}
	
sub main
	{
	# Does the work
	my $self=shift;
	
	verbose "Start\n";
	
	$self->useIfNecessary();
	
	my $testList;

	if (scalar(@_))
		{
		$testList = [@_];
		}
	else
		{
		$self->figureTestRoutines();
		$testList = $self->testRoutines;
		}
	
	my $target = $self->targetPackage;
	my $targetObj = undef;
	if ($target->can("new"))
		{
		$targetObj = $target->new();
		vverbose 4,"${target}->new()\n";
		}
	
	$gCountTests = 1;
	
	foreach my $test (@$testList)
		{
		vverbose 4,"test = $gCountTests $test\n";
		eval
			{
			no strict 'refs';
			$targetObj
				? $targetObj->$test()
				: &{$target."::$test"}();
			use strict 'refs';
			};
		if ($@)
			{
			_logStatus($target, $test."()", "DIED", $@);
			last;
			}
		}
	
	}

sub report
	{
	my $success = countStatus('    ');
	print "Success ",countStatus('    '),"\n";
	_report('    ');

	# other
	foreach (keys %gStatusNames)
		{
		next if /FAIL|DIED|    /;
		_report($_);
		}

	my $failures = countStatus('FAIL');
	print "Failures $failures\n" if $failures;;
	_report('FAIL');

	my $errors = countStatus('DIED');
	print "Errors $errors\n" if $errors;
	_report('DIED');
	awgrover::Report->Flush;

	print "Failures $failures\n" if $failures;
	print "Errors!\n" if $errors;
	print "Success/total = $success/".($success+$failures+$errors)."\n";
	}

sub countStatus
	{
	my ($status) = @_;

	my $ct=0;
	
	foreach my $package (keys %gStatus)
		{		
		my $stati = $gStatus{$package};
		next if ! exists $stati->{$status};

		$ct += scalar @{$stati->{$status}};
		}
	return $ct;
	}
	
sub _report
	{
	my ($desiredStatus) = @_;
		
	my $multiPackage = 1 < keys %gStatus;
	
	my $ct = 0;
	my $lastPackage="";
	
	foreach my $package (keys %gStatus)
		{		
		my $stati = $gStatus{$package};
				
		foreach my $status ($desiredStatus) # (keys %$stati)
			{
			next if ! exists $stati->{$status};
			
			awgrover::Report->PrintLine( "        ","","","$package") if $multiPackage && ($package ne $lastPackage) && (scalar @{$stati->{$status}} );
			$package = $lastPackage;
			
			foreach my $record (@{$stati->{$status}})
				{
				my $sequence = sprintf ("%3d", $record->{'sequence'} );
				awgrover::Report->PrintLine( "",$status," $sequence ",$record->{'location'},$record->{'message'});
				$ct ++;
				}
			}
		}
	return $ct;
	}
	
sub findUseTimeRoutines {}

sub figureTestRoutines
	{
	my $self=shift;
	
	return $self->testRoutines if $self->testRoutines;

	$self->findUseTimeRoutines();
	return $self->testRoutines if $self->testRoutines;
	
	
	my $target = $self->targetPackage;

	no strict 'refs';
	my $targetGlob = \%{$target."::"};
	use strict 'refs';
	
	
	my @symbols = keys %$targetGlob;
	vverbose 4, "$target sym ",join(",", @symbols),"\n";

	my @routineNames = grep { defined *{$targetGlob->{$_}}{CODE} } @symbols;
	vverbose 2, "routines ",join(",", @routineNames),"\n";
	
	my @tests = sort grep {/^test_/} @routineNames;
	vverbose 2, "tests ",join(",", @tests),"\n";
	
	if (! scalar @tests)
		{
		my $reason="";
		if (scalar (@symbols) <= 1)
			{
			$reason = ", 'package' statement might not equal file name/path" 
			}
		elsif (scalar (@routineNames) <= 1)
			{
			$reason = ", no methods/routines declared" ;
			}
		else	
			{
			$reason = ", no routines named beginning with 'test_'";
			}
		verbose "No tests in $target$reason   \n";
		
		}
	$self->testRoutines(\@tests);
	}

sub packageCheckPoint
	{
	# save list of current packages
	my $self=shift;
	
	my %existingPackages;
	@existingPackages{ grep {/::$/} keys( %::) } = (undef,);
	$self->packagesAtCheckPoint(\%existingPackages);
	}

sub checkForNewSymbols
	{
	# check if new symbols for target
	my $self = shift;
	my ($target) =@_;
	
	no strict 'refs';
		my $existingCt = scalar keys %{$target."::"};
	 		#verbose "$target has: ",join(" ",keys %{$target."::"}),"\n";
	use strict 'refs';
	
		
	verbose "Package $target appears empty, (no symbols)\n"
		if $existingCt <= 1; # has 'import' always
	}
	
use vars qw($gTestHarness_useTarget_line);
$gTestHarness_useTarget_line = 0;
	
sub useIfNecessary
	{
	# try to be too smart and only 'use' the target if necessary.
	my $self=shift;
	
	my $target = $self->targetPackage;
	
	no strict 'refs';
	my $existingCt = scalar keys %{$target."::"};
	use strict 'refs';
	
	return if $existingCt;
	
	$self->packageCheckPoint();
	
	eval {testHarness_useTarget($target)};
	
	$self->checkForNewSymbols($target);
	
	if ($@)
		{
		#print "## \$\@'d\n";
		if ($@ =~ /TestHarness\.pm/)
			{
			my ($line) = $@ =~ /line ([0-9]+)/;
			#print "## in TH \@ $line\n";
			if ($line == $gTestHarness_useTarget_line && $line)
				{
				#print "## at target line\n";
				warn $@;
					_logStatus($target, "", 'DIED',"Can't locate package $target");
				}
			else
				{
				die $@;
				}
			}
		else
			{
			die $@;
			}
		}
	
	}

sub testHarness_useTarget
	{
	# really just a require/import, but nested here so we can detect errors
	my ($target) = @_;
	
	my $pm = $target;
	$pm =~ s|::|/|g;
	$pm .= ".pm";
	
	# NB: leave both statements on same line for auto-detection
	$gTestHarness_useTarget_line = __LINE__;	require $pm;
	$target->import();
	
	}
	
sub logStatus
	{
	my ($package, $boolean) = (shift, shift);
	my $status = $boolean ? "    " : "FAIL";
	_exportedLogStatus($package,$status,@_);
	return $boolean;
	}

sub _exportedLogStatus
	{
	my ($package,$statusName) = (shift,shift);

	my ($routine, $line) = Callers::clientByPattern('test_[^:]+$'); #FIXME: use qr// to pass pattern to ::client()
	#vverbose 8,'($routine, $line) ',"($routine, $line)\n";
	$routine = '' if !$routine;
	$line = 0 if !$line;
	my $level = 3;
	my ($actualRoutine,$actualLine);
	do
		{
		($actualRoutine,$actualLine) = Callers::client($level);
		#vverbose 8,'($actualRoutine,$actualLine)',"($actualRoutine,$actualLine)\n";
		$actualRoutine = '' if !$actualRoutine;
		$actualLine = 0 if !$actualLine;
		$level ++;
		} while ($actualRoutine =~ /logStatus(_[^:]+)?$/);

	if (!$routine)
		{
		$routine = $actualRoutine;
		$line = $actualLine;
		}
	if ($actualRoutine eq $routine && $actualLine eq $line)
		{
		$actualLine= undef;
		}

	$routine =~ /::([^:]+)$/;
	
	my $methodName = $1 || $routine;
	
	my $formattedLine = $line . ($actualLine ? "($actualLine)" : "");
	_logStatus($package, "$methodName.$formattedLine", $statusName,@_);
	
	#print "$package ? $statusName : ",@_,"\n";
	}

sub logTodo
	{
	my ($package) = (shift);
	_exportedLogStatus($package,'TODO',@_);
	}

sub _logStatus
	{
	my ($package, $location, $status) = (shift, shift, shift);

	confess "No message" if ! scalar @_;
	
	no warnings 'uninitialized';
	my $message = join("",@_);
	use warnings 'uninitialized';

	chomp $message;
	
	$gStatusNames{$status} = undef;

	push @{$gStatus{$package}->{$status}}, 
		{package=>$package, location=>$location, message=>$message, sequence=>$gCountTests};

	$gCountTests++;
	}
	
sub import
	{
	my ($thisPackage) = shift;
	my ($routineName,$function) = @_;
	
	my $target = Callers->importerClass();
	die "Can't deduce importer class" if !$target;
	no strict 'refs';
	*{$target."::logStatus"} = sub { return logStatus($target, @_) };
	*{$target."::logTodo"} = sub { return logTodo($target, @_) };
	*{$target."::logStatus_eq"} = sub	# string eq
		{
		my ($a,$b) = (shift, shift);
		
		no warnings 'uninitialized';
		my $isEqual = $a eq $b;
		use warnings 'uninitialized';
		if (!$isEqual && $a && length($a) > 20)
			{
			$b = mismatchPoint($a,$b);
			}

		no warnings 'uninitialized';
		my $explanation = $isEqual ? "" : ", expected '$a', found '$b'";
		use warnings 'uninitialized';
		return logStatus($target, $isEqual, @_, $explanation) 
		};
	*{$target."::logStatus_ne"} = sub	# string ne
		{
		my ($a,$b) = (shift, shift);
		
		no warnings 'uninitialized';
		my $isNEqual = $a ne $b;
		use warnings 'uninitialized';
		
		my $explanation = $isNEqual ? "" : ", expected !'$a', found '$b'";
		return logStatus($target, $isNEqual, @_, $explanation) 
		};
	*{$target."::logStatus_equal"} = sub	# numeric ==
		{
		my ($a,$b) = (shift, shift);
		
		no warnings 'uninitialized';
		my $isEqual = $a == $b;
		use warnings 'uninitialized';
		
		no warnings 'uninitialized';
		my $explanation = $isEqual ? "" : ", expected '$a', found '$b'";
		use warnings 'uninitialized';

		return logStatus($target, $isEqual, @_, $explanation) 
		};
	use strict 'refs';
	$gLastTarget = $target;
	}
sub mismatchPoint
	{
	my ($expected,$actual) =@_;
	my @exp = split(//,$expected);
	my @act= split(//,$actual);

	my $actualWithPoint = '';
	my $len = scalar(@exp) > scalar(@act) ? scalar(@act) : scalar(@exp);
	my $soFar=1;
	for (my $i=0;$i<$len;$i++)
		{
		if ($soFar && $exp[$i] ne $act[$i])
			{
			$actualWithPoint .= "<*>";
			$soFar=0;
			}
		$actualWithPoint .=  $act[$i];
		}
	$actualWithPoint .= "<*>" if  $soFar && scalar(@exp) != scalar(@act);
	$actualWithPoint .= join("",@act[$len..$#act]) if $len < scalar(@act);
	return $actualWithPoint;
	}
1;
