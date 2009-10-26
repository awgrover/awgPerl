package Tests::Callers;
# invoke with perltest Tests::Callers

use Callers;
use TestHarness;

use vars qw($kCallLine $kCallLine1 $kCallLine2 $kCallLineP $kCallLineC $kCallLineC2);

#NB: Add tests to TestHarness: "use" mode

sub test_client
	{
	my $myName = getMyName(1);
	logStatus_eq('Tests::Callers::test_client',$myName,"client(1) gives name");
	$myName = getMyName();
	logStatus_eq('Tests::Callers::test_client',$myName,"client() gives name");
	$myName = getMyName(2);
	logStatus_eq('(eval)',$myName,"client(2) gives eval name (could be unreliable)");
	$myName = getMyName(10);
	logStatus_eq('',$myName,"client(10) gives empty name");

	my @info=	
		(
			1=>('Tests::Callers::test_client',$kCallLine),
			undef,('Tests::Callers::test_client',$kCallLine),
			10=>('',0),
		);

	for (my $i=0;$i<=$#info; $i+=3)
		{
		my ($level, $expName, $expLine) = @info[$i,$i+1,$i+2];
		
		my ($name, $line) = getMyName($level); BEGIN {$kCallLine = __LINE__};
		
		logStatus_eq($expName,$name,"client and line ($level), name");
		logStatus_equal($expLine,$line,"client and line ($level), lineNumber ");
		}
	}

sub test_clientByPattern
	{
	my @info=	
		(
		'^Tests::Callers::sub'=>('Tests::Callers::sub2',$kCallLine2),
		'^Tests::Callers::sub1'=>('Tests::Callers::sub1_x',$kCallLine1),
		'x$'=>('Tests::Callers::sub1_x',$kCallLine1),
		'::test_',('Tests::Callers::test_clientByPattern',$kCallLineP),
		'test_[^:]+$',('Tests::Callers::test_clientByPattern',$kCallLineP),
		);

	for (my $i=0;$i<=$#info; $i+=3)
		{
		my ($pattern, $expName, $expLine) = @info[$i,$i+1,$i+2];
		
		my ($name, $line) = sub1_x($pattern); BEGIN {$kCallLineP = __LINE__};
		
		logStatus_eq($expName,$name,"client and line /$pattern/, name");
		logStatus_equal($expLine,$line,"client and line /$pattern/, lineNumber ");
		}
	}

sub test_clientOfClass
	{
	my @info=	
		(
		'Tests::Callers_1->subImmediate'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_1->subNested'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_2->subImmediate'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_2->subNested'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_2->subInherited'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_2->subInheritedImmediate'=>('Tests::Callers::test_clientOfClass',$kCallLineC),
		'Tests::Callers_2->subCallNonSubClass'=>('Tests::Callers_2::subCallNonSubClass',$kCallLineC2),
		);

	for (my $i=0;$i<=$#info; $i+=3)
		{
		my ($routine,$expName, $expLine) = @info[$i,$i+1,$i+2];
		
		my ($name, $line) = eval "$routine()"; die $@ if $@; BEGIN {$kCallLineC = __LINE__};

		logStatus_eq($expName,$name,"client and line $routine(), name");
		logStatus_equal($expLine,$line,"client and line $routine(), lineNumber ");
		}
	}
		
		
sub getMyName
	{
	return Callers::client(@_);
	}

sub sub1_x
	{
	sub2(@_); BEGIN {$kCallLine1 = __LINE__};
	}

sub sub2
	{
	sub3(@_); BEGIN {$kCallLine2 = __LINE__};
	}

sub sub3
	{
	return Callers::clientByPattern(@_);
	}


#####

package Tests::Callers_1;

sub subNested {shift;subImmediate(@_);}
sub subImmediate
	{
	shift;
	return Callers::clientOfClass(@_);	
	}

package Tests::Callers_2;
@Tests::Callers_2::ISA=qw(Tests::Callers_1);

sub subInherited {my $class=shift;$class->subImmediate(@_)}
sub subInheritedImmediate
	{
	shift;
	return Callers::clientOfClass(@_);	
	}
sub subCallNonSubClass {shift; Tests::Callers_3->subImmediate()} BEGIN {$Tests::Callers::kCallLineC2 = __LINE__};

package Tests::Callers_3;
sub subImmediate
	{
	shift;
	return Callers::clientOfClass(@_);	
	}
1;

__END__
C
C_1	a,b clientOfClass => C
	C_2		b clientByPackage => C, d => C
C_3	c clientByPackage => C_2

		
sub nest {Tests::Callers_2::	
1;
