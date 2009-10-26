package WebApp::Session;
use base qw(Class::New);

use strict;
use warnings;
no warnings qw(uninitialized);

use Carp;
use Data::Dumper;
use IO::File;
use File::Path;
use Memoize;
use Verbose; $kVerbose =4;

use Class::MethodMaker get_set=>[qw(webApp _param existing)];

sub preInit
	{
	my $self=shift;

	$self->_param({});	
	}

sub load
	{
	my $self = shift;
	
	my $dirty_encoded = $self->webApp->request->cookie(%{$self->webApp->config()->{'cookieSpec'}});
	return if !$dirty_encoded;
	
	my ($encoded) = $dirty_encoded =~ /(.+)/; # FIXME: Not safe
	vverbose 0,"cookie '$encoded'\n";	
	
	$self->existing(1);
	
	no strict 'vars';
	$self->_param(eval $encoded); die $@ if $@;
	use strict 'vars';
	
	$self->_param({}) if !$self->_param;
	
	#vverbose 0,"parm is ",$self->_param,"\n";
	}

sub param
	{
	my $self=shift;
	if (scalar(@_) == 0)
		{
		return %{$self->_param};
		}
	elsif (scalar(@_) == 1)
		{
		my ($key) =@_;
		return $self->_param->{$key};
		}
	else
		{
		while (scalar (@_))
			{
			my ($key,$value) = (shift @_,shift @_);
			confess "only scalars, saw $key=>$value" if ref $value;
			$self->_param->{$key} = $value;
			}
		}
	}

sub sessionCookie
	{
	my $self=shift;
	
	my $cookieValue = Data::Dumper->new([$self->_param])->Indent(0)->Terse(0)->Dump();
	vverbose 0,"Cookie: $cookieValue\n";
	
	my $cookie = $self->webApp->request->cookie(
		%{$self->webApp->config->{'cookieSpec'}},'-value'=>$cookieValue
		);
	return $cookie;
	}
		
sub preparePageContext
	{
	my $self=shift; confess "no self" if !$self;
	
	$self->webApp->pageContext->{'session'} = $self->_param;

	}

1;
