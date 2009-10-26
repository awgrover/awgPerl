package LoadTest;
use base qw(Class::New);

=pod

Find out the maximum load for a command or set of commands.

Given a command, increase invocations/sec till saturation,
then increase till the command is too slow.

Run sysstat in conjunction with this, to find the limiting resource.

=head1 Theory of operation

Measure the response-rate to detect maximum loads, without having to have access to any other measures. Thus, this works remotely (e.g. http requests, ftp, etc.).

Run a test where the command is started at some rate (e.g. 1/sec). Do this long enough to
establish a consistent response-rate. Of interest will be the entire plot of time vs. response-rate, at this given load. One can estimate the initial time period by running 1 command and measuring how long it takes to complete. On systems with caching, this serves also to preload the cache.

(Optional: Collect statistics till the last command finishes, giving performance information about recovering from load).

Increase the start-rate. Measure. Repeat.

The response-rate (rate at which the commands finish) will increase untill commands are running concurrently (i.e. start to compete with each other). We'll call that "saturation."

After that, the response rate will decay, with a characteristic behavior related to the command.

Eventually, the system _may_ refuse to run commands concurrently, and queue them instead. The response-rate will suddenly jump, by an amount equal to the response-time. This could be called the max-listeners, or max-concurrency.

Instead, the system _may_ refuse to queue additionaly commands, and merely terminate them immediately with an error. This measures the same point as the above, but indicates no queuing.

In either of these cases (max-concurrency), we are still interested in the maximum load that still produces tolerable response-rates. Thus, we can increase load till we hit the 'tooSlow' value.

Less sophisticated systems (without a hard max-concurrency) may just continue adding concurrent processes, and the response-rate will continue to decay (typically exponentially). The 'tooSlow' parameter puts a limit on this, and tells us when to stop increasing load. This is then the max-tolerable-load.

=head1 Use:

See tests at bottom.

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Time::HiRes qw( gettimeofday tv_interval );
use Statistics::Descriptive;
use POSIX ":sys_wait_h";
use IO::File;

use overload '""' => 'toString';

our @kStatisticProperties;
BEGIN { @kStatisticProperties = 
	qw(
	interval responseTime iterations tailVariance stats
	elapsed tooFast
	);}

use Class::MethodMaker get_set => [qw
	(
	command tooSlow initialInterval noModSecs
	), 
	@kStatisticProperties
	];

=head1 new()

=head2 command => "..." | ["...","...",...]

The command you want to load test. It will be run in sh, by a system() call.

A list of commands will run sequentially.

=head2 initialInterval => $secs

Explicitly set the initial-interval between starting the command.

For a list, the interval between each command. Though I don't think that makes sense....

=cut

sub preInit
	{
	my $self=shift;
=test defaultValues
	default values
		my $l = LoadTest->new();
		assertDefined($l->tooSlow,"tooSlow defaulted") &&
		assertOp($l->tooSlow,">",0,"tooSlow > 0");
		
		$l = LoadTest->new(tooSlow=>9.5);
		assertDefined($l->tooSlow,"tooSlow set") &&
		assertEQ($l->tooSlow,9.5,"tooSlow set by new");
=cut	
	$self->tooSlow(20);
	}
	
	
sub run
	{
	my $self=shift;
	
	print join("\t",'Rate','ResponseTime'),"\n";
	$self->_setup;
	$self->increaseRateTillTooSlow;
	}

sub _setup
	{
	# Get ready to do the tests
	my $self = shift;
	$self->resetStats;
	$self->establishInitialRate;
	}
	
sub increaseRateTillTooSlow
	{
=test increaseRateTillTooSlow
	Check rate goes to tooSlow
		my $l = LoadTest->new(command => 'ls', tooSlow=>1, noModSecs=>1);
		$l->_setup;
		$l->increaseRateTillTooSlow;
		assertOp($l->responseTime,">=", $l->tooSlow,"Found max-tolerable");
		
		assertToDo("saveStatistics");
		assertToDo("responseTime");
=cut	
	my $self = shift;
	
	while ($self->responseTime < $self->tooSlow && $self->tooFast<5)
		{
		$self->tooFast(0);
		$self->mod5secs;
		$self->doCommandTillStable;
		$self->saveStatistics;
		$self->decreaseInterval;
		}
	warn "## out ",$self->responseTime,"<",$self->tooSlow,", ",$self->tooFast;;
	if ($self->tooFast>5)
		{
		warn $self->command," runs too fast to test (",$self->responseTime.")\n";
		}
	}

sub saveStatistics
	{}
	
sub doCommandTillStable
	{
=test doCommandTillStable
	Check statistics,
	should be several iterations
	variance should stabilize
		my $l = LoadTest->new(command => 'ls', tooSlow=>1, noModSecs=>1);
		$l->_setup;
		$l->doCommandTillStable;
		assertOp($l->iterations,">", 5,"Iterated some");
		#assertDefined($l->tailVariance,"Variance set") &&
		#assertNE($l->tailVariance,0,"Variance set");
		#assertOp($l->tailVariance,"<", .1,"Variance stabilized");
		
		#print "###########\n";
		$l->resetStats;
		#$l->interval($l->initialInterval/10);
		$l->interval(.1);
		$l->command('sleep 1');
		$l->doCommandTillStable;
		assertDefined($l->elapsed,"elapsed set") &&
		assertNE($l->elapsed,0,"elapsed set")  &&
		assertOp($l->elapsed,"<",$l->iterations+1, "Running concurrent");
		assertOp($l->elapsed,">=",($l->iterations-1)*$l->interval+1, "Respecting interval");

=cut	
	my $self=shift;

	my $runStart = [gettimeofday];
	
	$self->stats(Statistics::Descriptive::Sparse->new());
	$self->iterations (0);
	my $parentPid = $$;
	my  $statFile = "/tmp/loadTest.$parentPid";
	my $fh = IO::File->new(">$statFile")
		|| die "Can't write to $statFile, $!";
	$fh->close;
	
	my $cmd = $self->command;
	my $forkCommand = "/usr/bin/time -f '$$ %e' -o $statFile -a $cmd > /dev/null";
	while ($self->iterations < 20 || $self->elapsed<5)
		{
		my $start = [gettimeofday];	# can we start commands fast enough?
		
		#print $forkCommand,"\n";die;
		
		my $childPid = fork();
		die "Can't fork" if !defined $childPid;

		if (!$childPid)
			{
			exec($forkCommand);
			}
		
		#$self->stats->add_data($elapsed);
		#$self->tailVariance($self->stats->variance);
		#print "## ",$self->tailVariance," ",$self->stats->standard_deviation,"\n";
		$self->iterations($self->iterations+1);
		
		# Wait till the next interval to start another one
		my $nextStart = $self->interval - tv_interval($start);
		Time::HiRes::sleep($self->interval) if $nextStart > 0;
		
		# We can't cope if our interval is shorter than the time it takes us to start
		if ($nextStart <=0 && $nextStart > .8 * $self->responseTime)
			{
			$self->tooFast($self->tooFast+1) if $nextStart <=0;
			print "TF ",$self->interval,"<",$nextStart," took ",tv_interval($start),"\n" 
			}
		
		$self->elapsed( tv_interval($runStart)); # so far
		}
	
	# Wait for children to finish
	my $ct=0;
	while ((my $pid = waitpid(-1,0)) != -1) 
		{
		die "A child had an error $?" if $?>0;
		$ct++;
		};
	
	# Read stats
	my $stath = IO::File->new("<$statFile") || die "Can't read $statFile, $!";
	my @cmdTime = map {my ($cpid,$t) = split(' '); $t} <$stath>;		
	$stath->close;
	#unlink $statFile || die "Can't remove $statFile, $!";
	
	$self->stats->add_data(@cmdTime);

	$self->responseTime($self->stats->mean);
	$self->elapsed( tv_interval($runStart));
	warn "# finished $ct children, stats for ",scalar(@cmdTime)," avg "
		,$self->responseTime," interval ",$self->interval
		," rate would be ",1/($self->interval),"\n";
	print join("\t",1/($self->interval),$self->responseTime),"\n";
	}
	
=off forkModel
	#$SIG{'CHLD'} = sub {wait};
	while ($self->iterations < 20 || $self->elapsed<5)
		{
		my $start = [gettimeofday];	# can we start commands fast enough?
		my $childPid = fork();
		die "Can't fork" if !defined $childPid;

		if (!$childPid)
			{
			open(STDOUT ,'>/dev/null') 
				|| die "Can't redir STDOUT to /dev/null $!";
			my $cmdStart = gettimeofday;
			system($self->command);
			exit $? if $?;
			
			my $end = gettimeofday;
			my $fh = IO::File->new(">>$statFile")
				|| die "Can't write to $statFile, $!";
			print $fh $$," ", $end-$cmdStart,"\n";
			$fh->close;
			exit 0;
			}
		$children{$childPid} = $start;

		#$self->stats->add_data($elapsed);
		#$self->tailVariance($self->stats->variance);
		#print "## ",$self->tailVariance," ",$self->stats->standard_deviation,"\n";
		$self->iterations($self->iterations+1);
		
		# Wait till the next interval to start another one
		my $nextStart = $self->interval - tv_interval($start);
		Time::HiRes::sleep($self->interval) if $nextStart > 0;
		$self->tooFast($self->tooFast+1) if $nextStart <=0;
		print "TF ",$self->interval,"<",$nextStart," took ",tv_interval($start),"\n" if $nextStart <=0;
		
		$self->elapsed( tv_interval($runStart)); # so far
		}
	
	# Wait for children to finish
	my $ct=0;
	while ((my $pid = waitpid(-1,0)) != -1) 
		{
		die "A child had an error $?" if $?>0;
		$ct++;
		};
	
	# Read stats
	my $stath = IO::File->new("<$statFile") || die "Can't read $statFile, $!";
	my @cmdTime = map {my ($cpid,$t) = split(' '); $t} <$stath>;		
	$stath->close;
	unlink $statFile || die "Can't remove $statFile, $!";
	
	$self->stats->add_data(@cmdTime);

	$self->responseTime($self->stats->mean);
	$self->elapsed( tv_interval($runStart));
	warn "# finished $ct children, stats for ",scalar(@cmdTime)," avg "
		,$self->responseTime," interval ",$self->interval
		," rate would be ",1/($self->interval),"\n";
	print join("\t",1/($self->interval),$self->responseTime),"\n"
	}
=cut

sub decreaseInterval
	{
=test decreaseInterval
	Should go down
		my $l = LoadTest->new(initialInterval=>1);
		$l->decreaseInterval;
		assertOp($l->interval,"<",1,"Went down");
=cut
	# decrease interval by 10%
	my $self=shift;
	#$self->interval($self->interval - $self->interval * .1);
	my $wasRate = 1/$self->interval;
	$self->interval(1/($wasRate+1));
	}
	
sub resetStats
	{
=test resetStats
	Clear all the statistics
		my $l = LoadTest->new();
		foreach (@LoadTest::kStatisticProperties)
			{
			$l->$_('not cleared');
			}
		$l->resetStats;
		foreach (@LoadTest::kStatisticProperties)
			{
			assertUndef($l->$_(),"Cleared ->$_()");
			}
		
=cut	
	my $self = shift;
	foreach (@kStatisticProperties)
		{
		$self->$_(undef);
		}
	}
	
sub mod5secs
	{
=test mod5secs
	Wait till time is approximately mod 5 secs, so stats are easier
	to correlate.
		my $l = LoadTest->new();
		
		$l->mod5secs;
		my $secs = (localtime())[0];
		assertOp($secs % 5, '<=',1, "mod5secs worked");
		
		
		sleep 2;
		$l->mod5secs;
		$secs = (localtime())[0];
		assertOp($secs % 5, '<=',1, "mod5secs worked");
	
=cut
	my $self=shift;
	
	return if $self->noModSecs;
	
	warn "sync to mod5secs...\n";
	my $wallSecs = (localtime())[0];
	my $secs = ($wallSecs % 5);
		$secs = 5 - $secs if $secs;
	my $floatSecs = Time::HiRes::time();
	my $sleepDelay = ($secs % 5) - ($floatSecs - int($floatSecs));
	$sleepDelay += 5 if $sleepDelay < 0; # avoid negative (from quantizing)
	#warn $sleepDelay;
	Time::HiRes::sleep($sleepDelay);
	
	}
	
sub establishInitialRate
	{
=test 	establishInitialRate
	It should use the initialInterval arg from new, or 
	try the command and time it.
		assertTest(LoadTest->can('initialInterval')
			,"LoadTest has a initialInterval())");
			
		my $l = LoadTest->new(command => 'sleep 2', initialInterval=>1);
		assertEQ($l->initialInterval,1,"initialInterval stuck");
		
		$l->establishInitialRate;
		assertEQ($l->initialInterval,1
			,"establishInitialRate used initialInterval");
		assertEQ($l->interval,$l->initialInterval
			,"establishInitialRate copied initialInterval");
		
		$l->initialInterval(undef);
		$l->establishInitialRate;
		assertDefined($l->initialInterval
			,"establishInitialRate set initialInterval");
		assertOp($l->initialInterval,'>',2
			,"establishInitialRate did empirical test");
		assertOp($l->initialInterval,'<',3
			,"establishInitialRate did empirical test");
		assertEQ($l->interval,$l->initialInterval
			,"establishInitialRate copied initialInterval");
		
=cut
	my $self=shift;
	
	
	if (!defined $self->initialInterval)
		{
		
		my $start = [gettimeofday];
		
			open(my $wasOut ,'>&STDOUT') 
				|| die "Can't redir STDOUT to /dev/null $!";
			open(STDOUT ,'>/dev/null') 
				|| die "Can't redir STDOUT to /dev/null $!";
		my $stat = system($self->command);
			open(STDOUT,">&",$wasOut)
				|| die "Can't restore STDOUT $!";
		my $elapsed = tv_interval($start);
		
		die $self->command," won't run: ",($stat>>8) if $stat ne 0;
		
		$self->initialInterval($elapsed);
		}
		
	$self->interval($self->initialInterval);
	warn "InitialInterval = ",$self->initialInterval,"\n";
	}
	
sub toString
	{
	
	}
1;
__END__

=test objectStyle
	Need to make an object, and then use it
		assertTest(LoadTest->can('new'),"LoadTest has a new()");
		assertNoDie(sub {LoadTest->new() . ""},
			"LoadTest has a overloaded tostring)");
		assertNoDie(sub {LoadTest->new(command => 'ls', tooSlow => 2);}
			,"accepts args in new");
		assertTest(LoadTest->can('run'),"LoadTest has a run()");

=test expository
	Show how it works
	Given a command, increase invocations/sec till saturation,
	then increase till the command is too slow.
		my $l = LoadTest->new(
			#command => 'wget -q --timeout=5 --output-document=/dev/null http://www.nationaltribunenews.com/cgi-bin/st.cgi?',
			#command => 'wget -q --timeout=5 --output-document=/dev/null http://www.iworldlink.com/go.php >/dev/null',
			#tooSlow=>5,
			#initialInterval => 1);
			command => 'ls | awk "{print}"', tooSlow => 2);
			$l->noModSecs(1); # to avoid delays
		$l->run;
		print "$l\n";

=test scratch
		my $l = LoadTest->new(
			command => 'wget -q --timeout=5 --output-document=/dev/null http://www.bestreplica.us/new_products.php\?id=3',
			tooSlow=>5,
			initialInterval => 1);
		$l->noModSecs(1); # to avoid delays
		$l->run;
=cut

