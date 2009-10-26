package Blemish::CollectInfo;

=pod

=h1 Usage

	# assume command line args
	# You should control the perllib to prevent aliasing
	use Blemish::CollectInfo;
	main();
	
	# looks for default rules in './blemish.rules'
	# writes to log in './blemish.log'

See Blemish/blemish shell script

--- -checkpoint [rules] # create a checkpoint
--- -test	# test against checkpoint

=h1 Rules

A file has the following structure:

	<ruleType> 
		<argName> <argValue>
		...
	...

The <ruleType> is a module at Blemish::Rule::<ruleType>.

The arguments are relevant to that rule, and are passed as 
	<argName> => '<argValue>'
to the module's new(). See the modules.

=cut

use strict;
use warnings;

my $kBlemishLog = 'blemish.log';

sub main
	{
	my ($action,$ruleFileName) = @ARGV;
	$ruleFileName='blemish.rules' if !$ruleFileName;

	umask 0177;
	
	#(open STDERR,">>$kBlemishLog") || die "can't open $kBlemishLog $!";
	(open STDERR,"|./logger -t blemish") || die "can't open ./logger $!";
	
		
	die "action is -checkpoint or -test\n" if !defined $action || $action eq '' || $action !~ /^-checkpoint|-test$/;
	
	FIXME('untaint ruleFileNname');
	
	my $rules = readRules($action,$ruleFileName);
	
	my $fingerprint = getFingerPrint($rules);

	writeFingerprint($action, $fingerprint);
	
	copyRules($ruleFileName) if ($action eq '-checkpoint');

	diffFingerprints() if ($action eq '-test');	

	close STDERR || die "can't close the pipe to logger";
	}

sub copyRules
	{
	my ($ruleFileName) = @_;
	
	(open FH,"<$ruleFileName") || die "can't read rules '$ruleFileName' $!";
	(open OUTH,">checkpoint/blemish.rules") || die "can't write checkpoint/blemish.rules $!";
	
	while (<FH>) {print OUTH $_}
	
	close OUTH;
	close FH;
	}
	
sub diffFingerprints
	{
	die "no checkpoint" if !-f 'checkpoint/fingerprint';
	
	print `diff checkpoint/fingerprint test/fingerprint >&2`;
	}
	
sub writeFingerprint
	{
	my ($action, $fingerprint) = @_;
	$action =~ /^-/;
	my $dirname = $';
	
	##print "## writing\n";
	
	my $was=umask 0077;
	mkdir $dirname if !-e $dirname;
	umask $was;
	
	(open OUTH,">$dirname/fingerprint") || die "can't write to $dirname/fingerprint $!";
	
	print OUTH join("\n",@$fingerprint),"\n";
	
	close OUTH;
	}
	
sub getFingerPrint
	{
	my ($rules) = @_;
	
	my @fingerprint;
	
	FIXME('untaint the rule name');
	while (my ($rule,$args) = each (%$rules))
		{
		my $rulePackage = "Blemish::Rule::$rule";
		require "Blemish/Rule/$rule.pm";
		import $rulePackage;
		
		my $partial = $rulePackage->new(@$args)->build();
		
		#print "$rulePackage\n",join("\n",@$partial),"\n";
		
		push @fingerprint, @$partial;
		}
	
	return \@fingerprint;
	}
	
sub readRules
	{
	my ($action, $ruleFileName) =@_;
	$ruleFileName = 'checkpoint/blemish.rules' if ($action eq '-test');

	die "no rule file '$ruleFileName'" if !-f $ruleFileName || !-r $ruleFileName;

	
	(open FH,"<$ruleFileName") || die "can't read rules '$ruleFileName' $!";
	
	my %ruleSet;
	
	my $ct=0;
	my $rule='';
	
	while (<FH>)
		{
		$ct++;
		chomp;
		
		next if $_ eq '';
		next if /^#/;
		next if /^\s+$/;
		
		/^[^\s]/ && do
			{
			$rule = $_;
			#print "\t$rule\n";
			
			next;
			};
		
		/^\s([^\s]+)\s+/ && do
			{
			my ($argName,$arg) = ($1,$');
			if ($argName eq '')
				{
				print STDERR "line $ct: (rule $rule), leading space with no argName\n";
				next;
				}
			if ($arg eq '')
				{
				print STDERR "line $ct: (rule $rule), arg $argName has no value\n";
				next;
				}
			if ($rule eq '')
				{
				print STDERR "line $ct: No rule for '$argName $arg'\n";
				next;
				}
			#print "\t\t$rule($argName=>'$arg')\n";
			
			$ruleSet{$rule} = [] if ! exists $ruleSet{$rule};
			
			push @{$ruleSet{$rule}}, ($argName, $arg); # allow repeats
			};
		}
	
	close FH;
	return \%ruleSet;
	}

sub FIXME
	{
	#print STDERR "FIXME: ",@_,"\n";
	}
1;

