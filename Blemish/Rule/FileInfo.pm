package Blemish::Rule::FileInfo;
use Class::New;
@ISA=qw(Class::New);

use warnings;
use strict;
use File::Find;

sub preInit
	{
	my $self=shift;
	$self->{'info'} = [];
	$self->directories([]);
	$self->{'excludes'} = {};
	$self->{'excludePatterns'} = [];
	}
	
sub directories
	{
	my $self= shift;
	if (scalar @_)
		{
		($self->{'directories'}) = @_;
		}
	else
		{
		return $self->{'directories'};
		}
	}

use Carp;
sub excludes
	{
	my $self= shift;
	if (scalar @_)
		{
		my ($value) = @_;
		# leading / is absolute
		##print STDERR "## exc = $value\n";
		if ($value =~ m|^/|)
			{
			($self->{'excludes'}) = $value;
			}
		else
			{
			push @{$self->{'excludePatterns'}}, $value;
			}
			
		}
	else
		{
		return $self->{'excludes'};
		}
	}

sub exclude
	{
	shift->excludes(@_);
	}
	
sub directory
	{
	my $self= shift;
	if (scalar @_)
		{
		push @{$self->{'directories'}}, @_;
		}
	else
		{
		return undef;
		}
	}
	
sub build
	{
	my $self=shift;
	
	foreach ( @{$self->directories } )
		{
		find({ wanted => sub {$self->_build}, follow => 1 }, $_);
		}
	return $self->{'info'};
	}

sub _build
	{
	# called by File::Find
	my $self=shift;
	my $theFile = $_;
	
	if (exists $self->excludes->{$File::Find::dir})
		{
		$File::Find::prune = 1;
		return;
		}
	
	foreach my $pattern (@{$self->{'excludePatterns'}})
		{
		##print STDERR "## exclude pattern $pattern (against $File::Find::dir or $_) \n";
		if ($File::Find::dir =~ m{(/$pattern$)|(^$pattern$)} )
			{
			##print STDERR "##  prune $File::Find::dir\n";
			$File::Find::prune = 1;
			return;
			}
		return if (m{(/$pattern$)|(^$pattern$)});
		
		}
	
	# Why does this give no info sometimes?	
	my @statInfo = stat $_;
	@statInfo = stat $File::Find::fullname if (!defined $statInfo[9]);
	if (!defined $statInfo[9])
		{
		print STDERR "no info? $File::Find::fullname ($_)\n";
		return;
		}
		
	my ($sec,$min,$hour,$day,$mon,$year,$z,$yday) = gmtime($statInfo[9]);
	my $mode = $statInfo[2];
	my ($uid,$gid) = @statInfo[4,5];
	my $size = $statInfo[7];
	$size = 0 if (-d $File::Find::fullname);
	
	my $date = sprintf "%06o %05d:%05d %04d/%02d/%02d %02d:%02d:%02d %14d", $mode,$uid,$gid,($year+1900,$mon+1, $day,$hour,$min,$sec),$size;
	push @{$self->{'info'}},$File::Find::fullname."\t$date";
	}

1;
