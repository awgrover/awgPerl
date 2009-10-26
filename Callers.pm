package Callers;
# copyright 2002 Alan Grover (Ann Arbor, MI)

use Carp;

sub importerClass
	{
	# try to find the class that called import
	
	my $i=0;
	my ($class);
	while (1)
		{
		$class=(caller($i))[0];
		my $routine=(caller($i))[3];
		last if !$class;
		last if $routine=~/::import$/;
		#print "$routine = ",join("|",(caller($i))),"\n";
		$i++;
		}	
	confess "Can't find an importer class" if !$class;
	return $class;	
	}

=head1 client($upStack)

Returns the name of the routine up the stack (1 = immediateClient).
Default is 1.
Returns ($client, $lineNumber) in array context.
NB: Remember that the routine name includes the package name.

=cut

use strict;

sub client
	{
	my ($level) = @_;

	$level = 1 if !defined $level;

	my ($package,$line,$routine) = (caller($level+1))[0,2,3];
	#my $routine=(caller($level+1))[3];
	#my $line = (caller($level))[2];
	return wantarray ? ($routine,$line,$package) : $routine;
	}

=head1 clientByPattern($re)

Returns the name of the first routine up the stack that matches the pattern.
Could return undef.
Returns ($client, $lineNumber) in array context. NB: Remember that the routine
name includes the package name.

=cut

sub clientByPattern
	{
	# try to find the client, by re-patten
	my ($pattern) = @_;
	
	my $i=2;	# start above ourselves
	my ($routine, $line);
	while (1)
		{
		$routine=(caller($i))[3];
		$line = (caller($i-1))[2];
		last if !$routine;
		last if $routine =~ /$pattern/;
		#print "$routine = ",join("|",(caller($i))),"\n";
		$i++;
		}	
	return wantarray ? ($routine,$line) : $routine;
	}

=head1 clientOfClass()

Returns the name of the first routine up the stack that is not in this class, 
it's superclass, nor an eval (etc.).

Could return undef.

Returns ($client, $lineNumber,$package) in array context. 

NB: Remember that the routine name includes the package name.

NB: Here's a case that may not behave the way you want:
	package Class1;
	sub doSomething
		{
		my $self=shift;
		blah blah
		my $otherBeast = Class2->new();
		# I want to be considered the client of doMore()
		# But I'm not.
		$otherBeast->doMore(); 
		}
	
	package Class2;
	@ISA=qw(Class1);	# NB: Class2 is sublcass of Class1
	sub doMore
		{
		...
		my $client = Callers::ClientOfClass();
		# You might want this to return "Class1" in this case,
		# but, we are a subclass of Class1.
		# This will return whomever called Class1->doSomething().
		}
		
=cut

sub clientOfClass
	{
	# try to find the client, in a client class
	my ($pattern) = @_;

	# Figure out the caller's class (could be main == '' )
		my $targetCaller = (caller(1))[3];
		my $callerClass = _classOfClient($targetCaller);
	#print "#  called by $targetCaller\n";
	
	my $i=1;	# start above ourselves
	my ($package, $routine, $class, $line);
	while (1)
		{
		$i++;
		
		$routine=(caller($i))[3];
		$class = _classOfClient($routine);
		#print "# try $class :: $routine\n";
		
		# Skip evals, etc.
		next if $routine =~ /\(eval\)/;
		
		# Skip entries for this class, and it's superclasses
		next if $class eq $callerClass;
		if ($callerClass && $class)	# class could be ''
			{
			next if $callerClass->isa($class);
			next if $class->isa($callerClass);
			}
		
		($package,$line) = (caller($i-1))[0,2];
		last;
		}
	#print "## $routine \@ $line\n";	
	return wantarray ? ($routine,$line,$package) : $routine;
	}

sub _classOfClient
	{
	# figure out class
	my ($client) = @_;
	
	$client =~ /[^:]+$/;
	my $callerClass = $`;
	chop $callerClass; chop $callerClass; # remove '::'
	return $callerClass;
	}
	
1;
