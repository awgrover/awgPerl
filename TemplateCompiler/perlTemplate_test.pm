#!/usr/bin/env perl
package perlTemplate_test;

use strict;
use warnings;
no warnings 'uninitialized';

use TemplateToPerl;
use File::Temp;
use IO::File;
use Cwd;
use Verbose; 

our @gFiles;
	END { foreach (@gFiles) {unlink $_} }

sub main
	{
	#print `cd TemplateToPerl; perl -mUnitTestInLine -e UnitTestInLine::run Parse.pm`;
	#exit 0;
	#print `perl -mUnitTestInLine -e UnitTestInLine::run TemplateToPerl.pm`;
	
	my $rezH = File::Temp->new("/tmp/tmplXXXXXXXX")
		|| die "Can't write to a File::Temp; $!";
	push @gFiles ,$rezH->filename;

	# for onceFn:
		my $onceFnCount = 0;
		my @onceFnValue = qw(zero once more-than-once);

	my $obj = perlTemplate_test::TestObj->new();
	my %data =
		(
		simpleFn => sub {"interpolated fn value"},
		dieFn => sub {die "an interpolated fn that calls die"},
		scalar => 1,
		scalar1 => 'a scalar value',
		scalarInt => 9,
		scalarFloat => 1.3,
		htmlChars => '" quoted, & anded, <> compared "', 
		obj => $obj,
		hash => { a=>1, key1 => $obj, key2 => 'val2' },
		array => [ 1, $obj, 'elem2', 3 ],
		cleanArray => [ 1, 'elem2', 3 ],
		countingFn => sub { $onceFnCount++; $onceFnValue[$onceFnCount]; },
		zero => 0,
		empty => "",
		oneBlank => " ",
		anUndef => undef,
		qstringValue => "blah<>&\"' =#@%+blah",
		cwd => cwd(),
		);

	my ($template, $expected) = getTestData();
	
	my $expH = File::Temp->new("/tmp/expXXXXXXXX")
		|| die "Can't write to a File::Temp; $!";
	push @gFiles ,$expH->filename;
	print $expH $expected;
	$expH->close;

	my $rez = TemplateToPerl->new( datapool=>\%data, text => $template );
	print $rezH $rez->output;
	$rezH->close;

	my $diff = "diff ".$gFiles[0]." ".$gFiles[1];
	my $compared = `$diff`;
	print "FAILED\n",$compared,"FAILED\n" if $compared;
	print "OK\n" if !$compared;
	}

sub getTestData
	{
	my (@template, @expected);

	my $templateName = $ARGV[0] || "template_test.tmpl";
	my $dh = IO::File->new("<$templateName")
		|| die "Can't read $templateName, $!";
	while (<$dh>)
		{
		last if $_ eq "__EXPECTED__\n";

		push @template,$_;
		}
	die "Expected a template after __DATA__ in this file"
		if ! scalar(@template);
		
	while (<$dh>)
		{
		push @expected,$_;
		}
	die "Expected canonical result after template (after __EXPECTED__) in this file"
		if ! scalar(@expected);
	return (join("",@template),join("",@expected));
	}
package perlTemplate_test::TestObj;
use base qw(Class::New);

use Class::MethodMaker [scalar => 'volatile'];

sub init {shift->volatile(1)}
sub trueA {1}
sub volatize { my $self=shift; $self->volatile( $self->volatile +1); undef }
sub method2 {'meth2'}
sub method1 {shift}
sub madeIt {'made it'}

package perlTemplate_test;
main();

# Test template follows
# Everything (!) after __data__, till __expected__ is the template
# Everything (!) after __expected__ is the expected result

=To-do
	More general exp in IF
	Change include to: { {file:...}}
	Change slot to: $path, file: { {slot}}
	Allow '-' in tokens (opt).
	iter?
		$x = $coll, $y = $cb, (nested)
		$x,$y = $coll,$cb (zipper)
	Add formatting "as"
All changed to XSL?
	Generate an executable to collect the values.
	Values supplied as XML.
	Run the XSL.
Valid HTML/XML
	Use toke-parser, etc.
	Each attribute-value can be interpolated
	Each element-body can be interpolated.
	The content of if/iter/etc. is recursively processed.
=cut
