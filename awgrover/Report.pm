package awgrover::Report;
use Class::New;
@ISA=qw(Class::New);

=pod

Use

Report->PrintLine $a,$b,$c;
...
print Report->Flush;

The default Report object is $Report::DefaultReport. Instead, you can create an object for each report:

my $report = Report->new();
$report->PrintLine $a,$b,$c;
...
print $report->Flush;

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Verbose;
$kVerbose = 0;

use Class::MethodMaker get_set=>[qw( data )];

BEGIN
	{
	#$__PACKAGE__::DefaultReport = __PACKAGE__->new();
	}

sub preInit
	{
	my $self=shift;
	$self->data([]);
	}
		
sub PrintLine
	{
	my $self=shift;
	$self = $__PACKAGE__::DefaultReport if !ref $self;
	
	push @{$self->data()},[@_];
	}

sub Flush
	{
	my $self=shift;
	$self = $__PACKAGE__::DefaultReport if !ref $self;

	# Figure column widths
	my @widths;
	
	foreach my $aLine (@{$self->data})
		{
		my $i=0;
		foreach my $col (@$aLine)
			{
			$widths[$i] = length($col) if !defined $widths[$i] || length($col) > $widths[$i] ;
			$i++;
			}
		}
	vverbose 4,"Widths: ",join(",",@widths),"\n";

	my @columnFormat = map {"%-".$_."s"} @widths;
	pop @columnFormat;
	push @columnFormat, "%s";
	my $format = join("  ",@columnFormat);
	vverbose 4,"Format: $format\n";

	foreach my $aLine (@{$self->data})
		{
		no warnings 'uninitialized';
		printf	$format."\n", @$aLine;
		use warnings 'uninitialized';
		}
	
	$self->data([]);
	}

$__PACKAGE__::DefaultReport = __PACKAGE__->new();
1;
