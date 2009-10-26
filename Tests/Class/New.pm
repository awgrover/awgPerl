package Tests::Class::New;

use lib "../..";

=pod

FIXME: enhance testharness to create as obj, and run tests in order.
FIXME: enhance testharness to allow picking out tests.
FIXME: enhance testharness to describe the tests.


=cut

use strict;

use IC::TestHarness;

sub main
	{
	IC::TestHarness::Test
		(
			[qw(
			test_01minimalNew
			test_02noProto
			test_03hashInit
			test_04init
			)]
		
		);
	}
	
sub test_01minimalNew
	{
	my $obj = _testPackage->new();
	
	logStatus(defined $obj,"new() returned a defined value");
	logStatus(ref $obj,"new() returned a reference '$obj'");
	logStatus("_testPackage" eq ref $obj,"new() returned a blessed object in _testPackage, '$obj'");
	}
	
sub test_02noProto
	{
	my $obj = _testPackage->new();
	
	eval {$obj->new()};
	my $thrown = $@;

	logStatus($thrown, "Throw when doing (new via prototype) \$someObj->new()");
	
	my $detected=1==($thrown =~ /^Class::New FATAL NoProto:/);
	logStatus($detected, "Threw message 'Class::New FATAL NoProto:", !$detected  && " ('$thrown')"); 
	
	}

sub test_03hashInit
	{
	my $k='notASetter';
	my $class="_testPackage";
	my $obj = eval {$class->new(notASetter=>1)};
	my $err = $@;
	my $detected = 1==($err =~ /Class::New FATAL no such setter\/method '$k' in class '$class'/);
	logStatus ($detected,"Detected bad setter '${class}::$k' in new's args", $detected ? "" : " threw: $err");
	
	my $value=1;
	$k="aSetter";
	$obj = eval {$class->new($k=>$value)};
	$err = $@;
	$detected = $err eq "";
	logStatus ($detected,"Accepted new with setter '${class}::$k'", $detected ? "" : " threw: $err")
		|| die "Tests terminated, can't continue";
	
	$detected = $obj->{$k} == $value;
	logStatus ($detected, "Set value '$value' via new with setter '${class}::$k'",$detected ? "" : (" stored '",$obj->{$k},"'") );

	$value="97";
	$obj = $class->new($k=>$value);
	$detected = $obj->{$k} == $value;
	logStatus ($detected, "Set value '$value' via new with setter '${class}::$k'",$detected ? "" : (" stored '",$obj->{$k},"'") );
	
	my %values=(aSetter=>55, bSetter=>67);
	$obj = eval {$class->new(%values)};
	$err = $@;
	$detected = $err eq "";
	logStatus ($detected,"Accepted ${class}->new with setters ",join(",",keys %values),
		 $detected ? "" : " threw: $err")
		|| die "Tests terminated, can't continue";
	
	$detected = $obj->{'aSetter'} == $values{'aSetter'} && $obj->{'bSetter'} == $values{'bSetter'};
	logStatus ($detected, "Set values '",join(",",values %values),
		"' via new with setters ",join(",",keys %values),
		,$detected ? "" : (" stored '",join(",", @$obj{'aSetter','bSetter'}),"'") );

	}

sub test_04init
	{
	my $class="_testPackage";

	my $k='cSetter';
	my $value="init";
	my $obj=$class->new();
	my $detected = $obj->{$k} eq $value;
	logStatus($detected,"Called preInit",$detected ? "" : (" expected $k eq '$value', saw '",$obj->{$k},"'") );

	$k="copySetter";
	$detected = $obj->{$k} eq $value;
	logStatus($detected,"Called init",$detected ? "" : (" expected $k eq '$value', saw '",$obj->{$k},"'") );
	
	$k='cSetter';
	$value="override";
	$obj=$class->new(cSetter=>$value);
	$detected = $obj->{$k} eq $value;
	logStatus($detected,"New(...) overrode preInit",$detected ? "" : (" expected $k eq 'init', saw '",$obj->{$k},"'") );

	$k="copySetter";
	$detected = $obj->{$k} eq $value;
	logStatus($detected,"Called init for overrode",$detected ? "" : (" expected $k eq '$value', saw '",$obj->{$k},"'") );
	
	}
#
####
#
no strict;

package _testPackage;
use Class::New;
@ISA=qw(Class::New);

use strict;

sub preInit
	{
	my $self=shift;
	$self->cSetter("init");
	}

sub init
	{
	my $self=shift;
	$self->copySetter($self->{'cSetter'});
	}
		
sub aSetter
	{
	my $self=shift;
	my ($value) = @_;
	$self->{'aSetter'} = $value;
	}
sub bSetter
	{
	my $self=shift;
	my ($value) = @_;
	$self->{'bSetter'} = $value;
	}

sub cSetter
	{
	my $self=shift;
	my ($value) = @_;
	$self->{'cSetter'} = $value;
	}

sub copySetter
	{
	my $self=shift;
	my ($value) = @_;
	$self->{'copySetter'} = $value;
	}

#
####
#	
Tests::Class::New::main();
