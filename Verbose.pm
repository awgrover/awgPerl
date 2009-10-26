package Verbose;
# copyright 2002 Alan Grover (Ann Arbor, MI)

use strict;

=pod

Verbosity functions.

Example:
	package Mypackage;
	
	use Verbose;	# must be inside package
	$kVerbose=4;	# Verbosity's up to 4 will print
	
	verbose "Level 1 verbose message will print";
	vverbose 3,"Level 3 message will print";
	vverbose 5,"Level 5 message will not print unless you adjst \$kVerbose";

Use:
	
	use Verbose [verboseType];
	
	verbose expr,...;
	vverbose level,exper...;
	
The default verboseType is "Default" which prints to STDOUT, with a simple prefix like "[packageName]";

Provided verboseTypes include
	Warn	Prints to STDERR using "warn"
	Off		A noop print
Note the correct interraction between Warn and CGI::Warn.

The verboseTypes are just packages in Verbose::* space, so you can add your own.

Suggested verbosity levels:
	0	Once messages, titles, etc. Rarely used.
	1	Life cycle, like start/stop/count
	4	Major repetive loops, like each file
	8	Tedium, like each line of a file

=cut

use Callers;

use vars qw(%kAlreadyUsed);

sub import
	{
	my ($thisPackage, $typeArg) = @_;
	
	$typeArg = 'Default' if !$typeArg;
	
	# find target class
	my $targetClass = Callers::importerClass();
	
	# find verboseType
	my $verboseType = "Verbose::$typeArg";

	# gives mysterious compilation error if I "use" more than once	
	if (!exists $kAlreadyUsed{$verboseType})
		{
		eval "use $verboseType '$targetClass'"; die $@ if $@;
		$kAlreadyUsed{$verboseType}=1;
		}	
	my $eVerbose=0;	# for closure

	no strict 'refs';
	export(
		$targetClass,
		verbose=>sub 
			{
			&{"${verboseType}::vverbose"} ($targetClass,(caller(1))[3],(caller(0))[2],@_) if 1 <= $eVerbose;
			},
		vverbose=>sub 
			{ 
			my $level = shift;
			&{"${verboseType}::vverbose"} ($targetClass,(caller(1))[3],(caller(0))[2],@_) if $level <= $eVerbose; 
			},
		kVerbose=>\$eVerbose,
		);
	use strict 'refs';
	
	return 1;
	}

sub export
	{
	my ($targetClass, %toExport) = @_;
	
	while (my ($symbol, $glob) = each %toExport)
		{
		no strict 'refs';
		*{"${targetClass}::$symbol"} = $glob;
		use strict 'refs';
		}
	}

1;
