package UnitTestInLine;
# perl -mUnitTestInLine -e UnitTestInLine::run <testable file> [-<oneTestName>]
# NB: perl -mUUnitTestInLine -e UnitTestInLine::run -- [options] <testable file>...
# 	options: 
use base qw(Exporter);
@EXPORT = qw(assertNoDie assertEQ assertNE assertDie assertNoDie assertFalse assertDefined 
	assertTest assertUndef assertToDo assertOp);
@EXPORT_FAIL =('debug');

=head1 Usage

	=test myFunction()
		myFunction() is supposed to do something useful
			assertEQ(myFunction(),4);
			...
	=cut

Run tests with 'perl -mUnitTestInLine -e UnitTestInLine::run <thatFile>'

Bracket your test code with the pod-like comments '=test', '=cut'.

Provide an optional name to '=test'.

The first indented line (1 tab), is the description of the test block.

Lines indented 1 tab are otherwise treated as comments;

Lines indented 2 tabs or more are executed.

The code is placed in a "sub {..}", inside a synthesized package name.

Any errors in your code, or test-code, whether at compile-time or run-time, should be reported with the correct file-name and line-number.

==head2 Options

Ask for the options:

	perl -mUnitTestInLine -e UnitTestInLine::run -- -H

=head2 Caveats

Don't mess with @ARGV, since that's the list of files we are reading. If you need to mess with @ARG, "local" might work, or save @ARGV and restore it before finishing your test.

Your test code executes in package _inLineTest::blah.... Thus, you have to use fully qualified names for functions in the package under test (if they aren't imported).

Each test (from '=test') is in a synthesized function. Thus, "my" and "local" are limited to the scope of that test. Globals should be made with "our", or with full-package-names (tricky).

A unfortunate side-effect is a "use" or "require" elsewhere in your code will generate a bunch of "redefined" warnings.

If the file-undef-test executes code, rather than being a package of routines, that code will execute before your tests are run. This is ok for code that just initializes values/etc., but probably not what you want for files that do real work, e.g. command-line utilities.

The 'import' method is not called for your package in your file. I suppose that means that no symbols will be exported. If you need to test that (or need that behavior), explicitly 'import $yourPackage ...', or 'use $yourPackage' in your test code. 

You can't control the order of the tests, or rather, the order is fixed: last first. (why? because I tend to put the highest level function at the top of the file, so it's test would be earliest in the file, and we should really test the lowest level function, which is later in the file).

=head1 Some Details

The file to be tested is:

"Used", by 'require "$thePath"'. 

Is transformed by 1) commenting everything outside of '=test' blocks, 2) converting each '=test' into a "sub blah{...}", 3) commenting stuff in the '=test' if it starts with exactly 1 tab, 4) adding a "package", "use strict", and "use warnings" to the top, 5) adding a call to all the tests at the bottom, 6) eval'ing the whole thing, 7) being very clever to fixup "die" messages ($@) so they show the original file-name. All of this without changing line-numbers (by leaving all EOL's in place), so they are reliable for die/warn/etc.

Limitations:

All the files are run in the same process, so the second file has a "dirty" perl-environment (things are already "used", etc.). To be fixed by forking for each file.

When the die-message ($@) is fixed up, it is stringified. Thus, thrown objects are turned into strings. Since this is done after all your code has returned/thrown, you shouldn't see it, and it shouldn't matter. However, a signal handler will see the string, not the object; and the stringify method of the thrown object (see overload '""') will be called by this package.

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Verbose;
use awgrover::Getopt;
use Callers;
use IO::File;

our @gReport;
our $gFailCt;
our $gTestableFile;
our $gInhibitENDReport;
our $gTestName;
our $gAnonCount;
our ($gEvalNum, $gFileName);
our $gTheTest; # from command line: -<testName>
our $gSwitches;
our $gOriginalPid;
BEGIN {$gOriginalPid = $$};

sub run
	{
	eval { _run() };
	if ($@)
		{
		reportSummary();
		if (ref $@)
			{
			die $@;
			}
		else 
			{
			warn "\nTest runner failed:\n";
			die $@;
			}
		}
	}

sub _run
	{
	vverbose 1,"Start\n";
	getSwitches();

	my @summary;
	while ($gTestableFile = shift @ARGV)
		{
		# FIXME: should fork this section so each testable-file gets clean environment
		vverbose 1,"$gTestableFile\n";

		$gAnonCount = 1;

		(warn "Not a file: $gTestableFile") && next if (!-f $gTestableFile);
		
		my $FH = IO::File->new("<$gTestableFile") 
			|| (warn "Can't read $gTestableFile, $!" && next);
		my $prog = join("",<$FH>);
		$FH->close;

		my ($testProg,$tests) = convertToTestCode($gTestableFile,$prog);
		runTests($gTestableFile,$testProg,$tests);
		}

	}

sub runTests
	{
	my ($fileName,$prog,$tests) = @_;

	my $psuedoPackage = $fileName;
	$psuedoPackage =~ s/\W/_/g;

	my @desiredTests = grep { $gTheTest ? $gTheTest eq $_ : 1} @$tests; # reverse @$tests;
	my $testList = ";".join("();",@desiredTests)."()";
	
	# NB: we've carefully kept the line-numbers exactly the same
	# so, don't introduce any extra EOL's here either
	my $completeProg = # setup package space
		"package _inlineTest::$psuedoPackage;"
		."require '$fileName';"
		."use ".__PACKAGE__."; "
		."use strict; "
		."use warnings; "
		."no warnings 'uninitialized'; "
		.$prog	# the code
		.$testList # run the tests
		;

	# Assert subs can use these globals
	$gFileName = $fileName;
	
	vverbose 4,"###\n$completeProg";
		if ($gSwitches->{'showPerl'})
			{
			print $completeProg;
			return;
			}	

	$gEvalNum = evalNum();
	eval $completeProg; 
	if ($@)
		{
		# Careful here, fixAtInDieMessage() operates on $@
		my $failMessage = $@;
		$@ = $failMessage . $failMessage->stackTrace 
			if $kVerbose >= 2 && (ref $failMessage && $failMessage->can('stackTrace'));
		
		#vverbose 0,"### evalnum $gEvalNum, $@\n";
		fixAtInDieMessage($gEvalNum,$fileName);
		
		#warn $completeProg;
		die UnitTestInLine::TestCodeFailure->new
			(message=>"\nTest code failed:\n$@");
		}
	return;
	}

sub convertToTestCode
	{
	my ($fileName,$remainder) = @_;

	my @tests;
	my $soFar;
	while ($remainder)
		{
		last unless ($remainder =~ /^=test[ \t]*(.*)$/m);
		my ($normalCode,$podLine,$testBegins) = ($`,$&,$');
		$gTestName = $1;
		if (!$gTestName)
			{
			$gTestName = "inline test $gAnonCount";
			$gAnonCount++;
			}
		$gTestName =~ s/\W/_/g;
		push @tests, $gTestName;
		
		vverbose 4,"## NORMAL\n$normalCode## $podLine\n##BEGIN\n$testBegins\n";

		# count lines up to here.
		my @podLineNumber = $normalCode =~ /(\n)/g ;
		my $podLineNumber = scalar(@podLineNumber) +1;
		vverbose 4,"test\@$fileName:$podLineNumber\n";

		$normalCode =~ s/^/#/gm if $normalCode;

		$testBegins =~ /^=.*$/m || die "no '=cut' or other pod to terminate '=test' @ line $podLineNumber in $fileName\n";

		my $test = $`;
		$remainder = $&.$'; # NB: the last remainder is dropped

		# Comment 1 tab, insert setup code at beginning
		$test =~ s/^\t([^\t])/\t#$1/gm;
		my $setup = '$'.__PACKAGE__."::gTestName='$gTestName';";
		$setup .= 'warn "# '.$gTestName.'...\n";' if $gSwitches->{'progress'};
		$test =~ s/\n/\n$setup/; 
		vverbose 4,"!!\n$test\n";

		$soFar .= $normalCode."sub $gTestName { #".$podLine.$test."}";
		
		}

	vverbose 1,join("",@tests),"\n";
	
	_assert(0,"No testable sections") if !$soFar;
	
	#die "No testable sections ('=test') in $fileName\n" if !$soFar;
	return ($soFar, \@tests); # NB: soFar does not have the last remainder
	}

sub getSwitches
	{
	# pick off test-to-run
	#vverbose 0,"##",scalar(@ARGV)," ",join(",",@ARGV),"\n";
	
	if (scalar(@ARGV) > 1)
		{
		if ((($gTheTest) = $ARGV[-1] =~ /^-(.+)/) && $ARGV[-2] =~ /^[^-]/)
			{
			pop @ARGV;
			$gTheTest =~ s/\W/_/g;
			#vverbose 0,"thetest='$gTheTest' from ",$ARGV[-1],"\n";
			};
		}
		
	$gSwitches=awgrover::Getopt::GetOptions
		(
		''=>'--- [-- options] filesToTest... [-<oneTest>] # run tests',
		'help|h|H'=>'this',
		'showPerl|p' => 'print the perl that will be eval\'d',
		'verbose|V:i'=>"[n]\tverbosity",
		'progress' => 'Print progress as each test is run',
		);

	$kVerbose = $gSwitches->{'verbose'} || 1 if exists $gSwitches->{'verbose'};
	
	vverbose 1,"switches1: ",join(",",map {"$_=>".$gSwitches->{$_}} keys %$gSwitches),"\n";
	}

sub assertDefined
	{
	my ($a) = (shift);
	
	my $status = defined($a);
	my $msg = $status ? '. Gave defined value' : ". Unexpectely undef";
	_assert($status,@_,$msg);
	return $status;
	}

sub assertUndef
	{
	my ($a) = (shift);
	
	my $status = !defined($a);
	my $msg = $status ? '. Gave undef value' : ". Unexpectely defined '$a'";
	_assert($status,@_,$msg);
	return $status;
	}

sub assertToDo
	{
	_assert(0,"TODO: ",@_);
	}
		
sub assertFalse
	{
	_assert(0,"Forced fail: ",@_);
	return 0;
	}

sub assertTest
	{
	my ($bool) = (shift);
	
	_assert($bool,@_);
	return $bool;
	}

sub assertOp
	{
	# $a,">",$b
	my ($a,$op,$expected) = (shift,shift,shift);
	my $expr = '"'.quotemeta($a)."\" $op \"".quotemeta($expected).'"';
	my $status = eval $expr;
		croak $@ if $@;
	my $msg = $status ? ". Got expected $op '$expected'" : ". Expected $op '$expected', found '$a'";
	_assert($status,@_,$msg);
	return $status;
	}

sub assertEQ
	{
	my ($a,$expected) = (shift,shift);
	
	my $status = (ref($expected) eq 'Regexp') ? $a =~ $expected : $a eq $expected;
	my $msg = $status ? ". Got expected '$expected'" : ". Expected '$expected', found '$a'";
	_assert($status,@_,$msg);
	return $status;
	}

sub assertNE
	{
	my ($a,$expected) = (shift,shift);
	
	my $status = $a ne $expected;
	my $msg = $status ? ". Got expected '$a' ne '$expected'" : ". Expected !='$expected', but found it";
	_assert($status,@_,$msg);
	return $status;
	}

sub assertNoDie
	{
	my ($sub) = (shift);
	
	my $evalNum = evalNum();
	my $rez = eval { &$sub() };
	if ($@)
		{
		my ($fn,$line) = Callers::client(0);

		fixAtInDieMessage($evalNum,"$gTestableFile", $line);
		fixAtInDieMessage($gEvalNum,$gFileName);
		chomp $@;
		}
	
	my $thrown = $@;
		
	my $msg = $thrown ? 
		". Died unexpected: $thrown"
		: ". Didn't die" 
		;
	vverbose 0,"(||) $msg\n" if $thrown;

	_assert(!defined($thrown) || $thrown eq '',@_,$msg);
	return $thrown ? 0 : $rez;
	}
		
sub assertDie
	{
	my ($sub,$re) = (shift,shift);
	$re = [$re] if ref($re) ne 'ARRAY';
	
	my $evalNum = evalNum();
	eval { &$sub() };
	if ($@)
		{
		my ($fn,$line) = Callers::client(0);

		fixAtInDieMessage($evalNum,"$gTestableFile", $line);
		fixAtInDieMessage($gEvalNum,$gFileName);
		chomp $@;
		}
	
	my $thrown = $@;
	
	my $finalStatus = 1;
	foreach (@$re)
		{
		$_ = qr/.*/ if ref($_) ne 'Regexp';
		my $status = $thrown =~ $_;

		my $expectedHead = substr($_,0,30)."...";
		my $foundHead = substr($thrown,0,30)."...";
		
		my $msg = $status ? 
			". Died as expected: $expectedHead ($foundHead)"
			: ($thrown ? ". Died, but expected $_, found: ".$thrown : ". Didn't 'die', expected $_" )
			;
		vverbose 0,"(||) $msg\n" if !$status;

		$finalStatus &= _assert($status,@_,$msg);
		}
	return $finalStatus;
	}

sub xassertNoDie
	{
	my ($sub) = shift;

	my $evalNum = evalNum();
	eval { &$sub() };
	my $status = $@ eq '';
	
	if ($@)
		{
		my ($fn,$line) = Callers::client(0);

		fixAtInDieMessage($evalNum,"$gTestableFile", $line);
		chomp $@;
		}
	my $msg = $status ? ". Didn't 'die'" : ". Unexpected 'die': ".$@;
	vverbose 0,"(||) $msg\n" if !$status;

	_assert($status,@_,$msg);
	return $status;
	}

sub evalNum
	{
	# figure out current "eval" number
	eval 'die'; # must be a string!
	my ($num) = $@ =~ /\(eval (\d+)\)/;
	return $num+1;
	}
	
sub fixAtInDieMessage
	{
	my ($evalNum,$str, $line) = @_;
	my $rep = $str;

	my $doLine = '';
	if (defined($line))
		{
		$doLine = ' line \d+';
		$rep = "$str line $line";
		}
	$@ =~ s/\(eval $evalNum\)$doLine/$rep/;
	}

sub _assert
	{
	my ($status) = shift;
	
	my ($line,$subroutine);
	my $frameLoc=1;
	# find first frame that is not "assertxxx()"
	do
		{
		my @info = caller($frameLoc);
		$line = (caller($frameLoc))[2];
		$subroutine = (caller($frameLoc+1))[3];
		$frameLoc++;
		} while ($subroutine =~ /::assert[^:]+$/);
	
	my $name = $gTestName;
	$gFailCt++ if !$status;
	push @gReport, ($status 
		? '     ' 
		: 'FAIL ').join("","[${gTestableFile}::$name.$line] ",@_)
		;
	return $status;
	}


sub reportSummary
	{
	return if $gInhibitENDReport;
	return if $$ ne $gOriginalPid;

	print "## Test Summary\n";
	print join("\n",@gReport)."\n";
	print "## Failures: ".($gFailCt+0)."\n";
	
	$gInhibitENDReport = 1;
	}

sub export_fail {warn "### export_fail: saw ",@_};

END {reportSummary()}

package UnitTestInLine::TestCodeFailure;
use base qw(Class::New);
use overload '""'=>'toString';

use Class::MethodMaker get_set=>[qw(message)];

sub toString
	{
	return shift->message;
	}
1;
