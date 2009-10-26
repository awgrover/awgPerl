=pod

=head1 usage

=head1 directory layout

Assumes:
	
	bin/yourCGI
	conf/conf.pm	# do a 'ln -s' to the machine/instance config
	lib/operations	# holding operations
	lib/	# the rest of your code, typically domain objects
	template/	# the templates

=head2 config

Put your config in conf/config.pm. The last line of the file returns a hash-ref:

	blah blah
	my %config = (
		urlBase => '/absolute/path/toApp',	# for cookies, default=absolute url (cgi->url('-absolute'))
		appName => 'bobs great app',
		);
	return \%config;

=head2 the cgi

	BEGIN {
		use CGI::Carp qw(carpout);
		open(LOG, ">>error_log") or
			die("Unable to open error_log: $!\n");
		carpout(LOG);
	}
	
	Package _yourWebApp;	# a package is required
	use base qw(WebApp::WebApp);
	use Memoize;
	
	memoize('config'); # for performance
	sub config
		{
		my $self=shift;
		my $configFromFileAndOtherSetup = $self->SUPER::config;
		return {
			%$configFromFileAndOtherSetup,
			imageUrl => $configFromFileAndOtherSetup->{'urlBase'}."/../bobsimages",
			moreInitialSlots=>andTheirValues,
			};
		}
	
	sub setPageContext_general
		{
		my $self=shift;

		$self->SUPER::setPageContext_general();
		
		# Put objects in the context: all requests
		$self->pageContext->{'catalogRoot'} = CatalogRoot->new,
		$self->pageContext->{'templateInstant'} = sub {time()};
		$self->pageContext->{'names'} = ['bob', 'joe', 'jane'];
		
	# Go
	__PACKAGE__->new()->main();

=head2 Templates

=head3 URL -> File mapping

If your "urlBase" is "/path/to/app", then create templates for each url you want to handle:

	/path/to/app	->	templates/index.tmpl
	/path/to/app/login	-> templates/login.tmpl
	/path/to/app/category/humans	-> templates/category/humans.tmpl 

NB: The last will actually use for templates/category.tmpl if it exists.

=head4 Template language

	Write normal HTML with {{...}} for interpolation, "if", "iterate", and "include".
	
	{{iterate $aRow $names}}
	<tr><td>The Name is {{$aRow}}</td></tr> <-- repeated for each in $names -->
	{{enditerate}}

=head1 Query-Params, getting objects, form-submits

OR, how to change the state of your objects.

Requests specify the template they want to see, and may list operations to perform before the template is rendered.

Operations are specified by query-params (GET or POST).

	http://blah/blah?op=fnName(p1Name=>p1Value,p2Name=>p2Value)

More on making that work with forms later.

This calls 

	my $o = WebAppOperation::fnName->new(webApp=>$theWebApp, subPath=>$theWebApp->subPath);
	$o->do(p1Name=>p1Value,p2Name=>p2Value)

The operation can add to the datapool via 
	
	$theWebAPp->pageContext->{'yourKey'} = $yourValue...

If there is an error, see {{$error}}
=cut

package WebApp::WebApp;
use base qw(Class::New);

use strict;
use warnings;
no warnings qw(uninitialized);

use CGI;
use Verbose; $kVerbose =4;
use TemplateToPerl;
use WebApp::Session;
use Carp;
use Memoize;
use IO::Dir;

use Class::MethodMaker get_set=>[qw(
	request pageContext newCookies subPath marshallSubPath
	_session
	)];

# sub pageContext
# 	{
# 	my $self = shift;
# 	
# 	if (scalar @_)
# 		{
# 		vverbose 0,"SET ",@_,"\n";
# 		$self->_pageContext(@_);
# 		}
# 	else
# 		{
# 		use Carp; confess if !$self;
# 		return $self->_pageContext;
# 		}
# 	}
	
sub init
	{
	my $self=shift;
	
	$self->request(CGI->new());
	$self->pageContext({});
	$self->subPath("");
	$self->newCookies([]);
	
	($ENV{'PATH'}) = $ENV{'PATH'} =~ /(.+)/; # clear taint
	}

memoize('config');	
sub config
	{
	my $self = shift;
	
	our $kConfigFileName = '../conf/conf.pm';
	
	my $config = do '../conf/conf.pm' || ((warn "../conf/conf.pm $!") && {});
	#use Cwd;
	#vverbose 0,"config ".cwd()."/../conf/conf.pm, type = '$config'\n";
	die "$kConfigFileName must return a hash-ref"
		if ref($config) ne 'HASH';
	#vverbose 0,"config keys ",join(",",keys %$config),"\n";

	my @base =
		(
		cookieSpec => {'-name'=>'session', '-path'=>$self->request->url('-absolute'), -expires=>'+1y'},
		templateDir => '../template',
		marshallDir => '../marshall',
		dataDir => '../data',
		);
	
	return {@base,%$config};
	}

sub main
	{
	eval {shift->_main(@_)};
	if ($@)
		{
		my $thrown = $@;
		warn $thrown;
		my @pieces = grep {$_} split(/(.{0,72})/s,$thrown);
		my $wrapped = join("\n\t",@pieces);
		print CGI->new->header('-status'=>500,'-status-message'=>"Failed");
		print <<"EOS";
<html>
	<head><title>Internal Error</title></head>
	<body><h3>Internal Run-Time Error</h3>
	<pre>$wrapped</pre>
	</body>
</html>
EOS
		}
	}
	
sub _main
	{
	my $self = shift;
	
	my $path = $self->request->path_info;
	vverbose 0,"\n\n-----------",$self->request->url('-absolute'),"$path\n";
	
	$self->checkRequest || ((vverbose 1,"checkRequest() stopped processing") && return);
	
	my $marshaller;
	my $template = $self->findTemplate($path);
		
	if (!$template)
		{
		if ($path)
			{
			$self->request->header('-status'=>404,'-status-message'=>"Unknown page");
			$self->pageContext->{'error'} = "Unknown Page '".$self->request->path_info."'";
			}
		$template = 'index';
		}
	else
		{
		$marshaller = $self->findMarshaller($path);	
		}
	
	my $opError = $self->doOperations(); # before or afer marshaller->new?
	

	$self->setPageContext_general();
	
	if ($marshaller)
		{
		$marshaller->marshall($self);
		}

	#use Data::Dumper; vverbose 0,"pageContext ",Dumper($self->pageContext);
	$self->display( 
		template => $template,
		);
	}

sub checkRequest
	{
	# Return true to process the request, false to return immediately
	# No processing has been done at this point.
	1;
	}
	
sub formattedServerNow
	{
	# for the web page, should be the server's time!
	# maybe make this cached so it's really the request time
	
	# FIXME: ask the designated machine for it's time
	my @t=localtime();
	return sprintf("%.4d.%.2d.%.2d %.2d:%.2d:%.2d",$t[5]+1900,$t[4]+1,@t[3,2,1,0]);
	}
	
sub setPageContext_general
	{
	my $self=shift;
	
	# Request
	$self->pageContext->{'serverNow'} = sub {$self->formattedServerNow};
	$self->pageContext->{'subPath'} = $self->subPath;
	$self->pageContext->{'urlSelf'} = $self->request->url('-path'=>1,'-absolute'=>1);
		
	# Session
	$self->sessionOrNew->preparePageContext();	
	
	}
	
sub sessionOrNew
	{
	my $self = shift;
	
	if (!$self->_session)
		{
		$self->_session(WebApp::Session->new(webApp=>$self));
		$self->_session->load();
		}
	return $self->_session 
	}
	
sub session
	{
	my $self=shift;
	
	my $session = $self->sessionOrNew();
	
	#confess "Needs session" if ! $session->existing;
	
	return $session;
	}
		
sub findMarshaller
	{
	my $self=shift;
	my ($path) = @_;
	
	my ($cleanedPath) = $path =~ m|^([\w/\.]+)$|;
	
	my $marshallDir = $self->config->{'marshallDir'};
	my ($file,$subPath) = $self->findFileByPath($cleanedPath,$marshallDir,'.pm');
	$self->marshallSubPath($subPath || $cleanedPath);
	vverbose 4,"marshall file '$file'\n";
	
	return undef if !$file;
	
	require $file;
	my $package = $file;
	$package =~ s/\.[^.]+$//; # remove .pm
	$package =~ s|^[./]+||; # remove leading ../
	$package =~ s|/|::|g; # change to ::
	vverbose 0,"package '$package'\n";
	
	return $package->new();
	}
	
sub findTemplate
	{
	my $self=shift;
	my ($path) = @_;
	
	$path="/index" if !$path || $path eq '/';
	
	my $templateDir = $self->config->{'templateDir'};
	my ($template,$subPath) = $self->findFileByPath($path,$templateDir,'.tmpl');
	if (!$template) {$template = $templateDir.$path.'.tmpl';}
	$self->subPath($subPath || $path);
	vverbose 4,"template '$template'\n";
	return $template;
	}
	
sub findFileByPath
	{
	my $self=shift;
	my ($path, $baseDir, $ext) = @_;
	
	$path =~ s/\.html?$//;
	vverbose 8,"find '$path$ext' in $baseDir\n";
	my $fullSubPath;
	
	while ($path ne '')
		{
		my $candidate = "$baseDir$path$ext";
		vverbose 0,"try '$candidate'\n";
		return ($candidate,$fullSubPath) if (-f $candidate);
		
		my ($subPath) = $path =~ /(\/[^\/]+)$/;
		$path = $`;
		$fullSubPath = $fullSubPath.$subPath;
		#vverbose 0,"trimmed '$subPath', ",$fullSubPath,"\n";
		# $path.html
		# $path.pm
		# trim /... off end
		}
	
	vverbose 0,"No ",$_[1],$_[0],"\n";
	return undef;	
	}
	
sub doOperations
	{
	my $self = shift;
	
	$self->pageContext->{'operation.errors'} = [] 
		if !defined $self->pageContext->{'operation.errors'};
	my $results = $self->pageContext->{'operation.errors'};
		
	my $error = 0;	
	my @ops = $self->request->param('op');
	foreach my $fnCall (@ops)
		{
		next unless $fnCall;
		
		#vverbose 0,"op='$fnCall'\n";
		
		my ($fn,$args) = $fnCall =~ /^(\w+)(?:\(([^\)]*)\))/;
		my $packageName = "WebAppOperation::$fn";
		my $fileName = "WebAppOperation/$fn.pm";
		#vverbose 0,"decode '$fnCall'('$args')\n";
		
		eval "require $packageName;" ; my $errorLine = __LINE__;
		if ($@ 
			&& $@ =~ /Can't locate $fileName in \@INC/ 
			&& $@ =~ / at \(eval /
			&& $@ =~ /line 1\./
			)
			{
			warn "Unknown '$packageName' attempted";
			warn $@;
			$self->pageContext->{'error'}= "Unknown operation attempted: '$fn'";
			return 'Failure';
			}
		if ($@)
			{
			vverbose 0,"line = $errorLine\n";
			confess $@;
			}
		
			# FIXME: check for do()
				
		#vverbose 0,"Call '$fnName' with ('$args')\n";
		my @argList = split(/,|=>/,$args);
		push @argList,undef if $args =~ /(,|=>)$/;
		
		vverbose 2,"Call '$packageName->do' with ('",join("','",@argList),"')\n";
		
		my $opObject = $packageName->new(webApp=>$self, subPath=>$self->subPath);
		$error = $opObject->do(@argList);
		
		}
	return $error;
	}

sub display
	{
	my $self = shift;
	my %args = @_;
	my ($params, $templateName) = delete @args{qw(params template)};
		croak "Unknown arguments '",join("','",sort(keys %args)),"'" if scalar keys %args;

	#my $fullTemplateName = $self->config->{'templateDir'}."$templateName.tmpl";
	vverbose 0,"filename=$templateName","\n";
	my $template = TemplateToPerl->new(
		filename => $templateName,
		datapool => $self->pageContext,
		#die_on_bad_params=>0,
		#case_sensitive=>1,
		#global_vars=>1,
		);


	my @cookie = $self->_session ? ('-cookie'=>$self->session->sessionCookie) : ();
	print $self->request->header(@cookie);

	eval { print $template->output; };
	if ($@)
		{

		if (ref($@) && $@->isa('TemplateToPerl::NoTemplateException'))
			{
			warn "No such file: $templateName";
			warn "Expected .tmpl, not .html" if -f $self->config->{'templateDir'}."/$templateName.html";
			print <<'EOS';
<html>
	<head><title>Not Found</title></head>
	<body><h3>No such page</h3></body>
</html>
EOS
			}
		else
			{
			warn $template->perlCode;
			die $@;
			}
		}
	}

1;

