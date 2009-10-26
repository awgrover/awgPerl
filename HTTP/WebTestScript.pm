package HTTP::WebTestScript;
use base qw(Exporter);
#BEGIN { $Exporter::Verbose=1}
@EXPORT    = qw(
	hw_baseurl 
	hw_log
	get
	name
	step
	fail
	clickLink
	extract
	forgetCookies
	onResponse
        %BasicAuth
	); #afunc $scalar @array)

use HTTP::WebTestScript::Log;
use HTTP::WebTestScript::Plugin::Form;
	push @EXPORT, @HTTP::WebTestScript::Plugin::Form::EXPORT;
use HTTP::WebTestScript::Plugin::Verify;
	push @EXPORT, @HTTP::WebTestScript::Plugin::Verify::EXPORT;

use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use URI;
use IO::File;
use Carp;
use HTTP::Cookies;

use strict;
use warnings;
no warnings 'uninitialized';
our $SpuriousText = chr(160); # chr(0xef).chr(0xbf).chr(0xbd);
our %BasicAuth; # username=>password
use Verbose; $kVerbose=0;

our (
	$gLog, 
	$gBaseUrl, 
	$gRequest, 
	$gResponse, 
	$_UA, 
	%gCurrentTest,
	$gLogToSTDERR,
	$gTimestamp,
	$gSaveCt,
	$gNameIsOpen,
	@gOnResponse,
        $gAllowFailure, # don't die on ! success
	);

$gSaveCt = 0;
	
sub UA
	{
	return $_UA if $_UA;
	
	$_UA = HTTP::WebTestScript::UserAgent->new(cookie_jar=>HTTP::Cookies->new());
	push @{ $_UA->requests_redirectable }, 'POST';
	return $_UA;
	}

=pod

=head1 hw_baseurl 'url to use for relative urls'

You'llneed Crypt::SSLeay to do https.

=cut

sub hw_baseurl
	{
	# set the base url for relative urls
	($gBaseUrl) = @_;
	}

=pod

=head1 hw_log directory for logs

Otherwise, logging is to STDERR

=cut

sub hw_log
	{
	($gLog) = @_;
	if (! -e $gLog)
		{
		mkdir $gLog || die "Can't make directory $gLog, $!";
		}
	if (! -d $gLog)
		{
		die "Expected a directory for hw_log ('$gLog'), but it wasn't";
		}

	}

=head1 fail "comment"

Fail. Useful for constructs like:

	(test not=1, text=>"Hobbits") && (test not=1, text=>"Dwarves") && fail "no heros available";

Note the use of "not" so that the log reads with successes unless there is a failure.

=cut

sub fail
	{
	my ($comment) = @_;
	
	trace(0,failed=>{description=>$comment});
	croak "\nFailed: $comment";
	}
	
=head1 get 

=head2 get url

Fetches the absolute or relative url. If html_save is on, saves to the hw_log directory (under the url name).

Returns the HTTP::Response. Sets $gRequest, $gResponse;

Dies on !$gResponse->is_success;

=head2 Hints

if defined($gResponse->previous) { warn "there was a redirect or 'unauthorized'" }

=cut

sub get
	{
	my ($comment) = scalar(@_) >1 ? shift : undef;
	my ($url) = @_;
	
	_get(command=>'get',url=>$url,method=>'get',base=>$gBaseUrl, description=>$comment);
	}
	
sub _get
	{
	my (%args) = @_;
	my ($command,$url,$method,$params, $comment, $base, $fileUpload, $debug) = delete @args{qw(command url method params comment base fileUpload debug)};
	$method = 'GET' if !defined $method;
	$method = uc($method);
	
	croak "URL was empty" if !$url && $method eq 'GET';
	#warn $url;
	
        # vverbose 0,"url->abs, using base=$base, resp->base=".( $gResponse ? $gResponse->base : '') . ", gbaseurl=$gBaseUrl";
        # vverbose 0,"Will use base: ".($base || ( $gResponse ? $gResponse->base : $gBaseUrl) || "http://");
        # allow a form to have no/empty action
        # vverbose 0,"url $url";
	my $uri;
        if ($method eq 'POST' && $gResponse && $url eq '') {
            $uri = $gResponse->request->uri->clone;
            $uri->query(undef);
            }
        else {
            $uri = URI->new_abs($url,
                $base || ( $gResponse ? $gResponse->base : $gBaseUrl) || "http://");
            }
        # vverbose 0,"Used $uri (where request was ".($gResponse ? $gResponse->request->uri : "no response object").") for POST" if $method eq 'POST';
	#vverbose 0,"$uri fileUpload? $fileUpload\n";
	#vverbose 0,"args ",join(",",%args),"\n";
	# vverbose 0,"Will $method ".$uri->as_string." with params ",Dumper($params),"\n"; use Data::Dumper;

        my $header = HTTP::Headers->new();
        if (keys(%BasicAuth)) {
            $header->authorization_basic(%BasicAuth);
            }

	if ($method eq 'GET')
		{
                $uri->query_form(ref($params) eq "HASH" ? %$params : @$params) if ($params);
		$gRequest = HTTP::Request->new(GET => $uri, $header);
		}
	elsif ($method eq 'POST')
		{
                my @headers;
                $header->scan(
                    sub {
                        my ($name,$value) =@_;
                        push @headers, ($name,$value);
                        }
                        );
		$gRequest = POST($uri,$params, @headers, $fileUpload ? (Content_Type=>'form-data') : ());
		}
	else
		{
		die "Unknown method '$method'";
		}
		
	die "Content\n",$gRequest->content,"\n " if $debug;
	$gResponse = UA->request($gRequest);
	
	my @size = ($gResponse->is_success) ? (bytes=>length($gResponse->content)) : ();
	my @content = ($gResponse->is_success) ? () : (content=>$gResponse->status_line);
	
	my $savedFile = saveHTML($gRequest,$gResponse);
	my @saved = $savedFile ? (savedfile=>$savedFile) : ();
	
	trace($gResponse->is_success,
		$command=>{method=>$method, uri=>$uri->as_string,
			http_status=>$gResponse->code,@content, @size, @saved,
			description=>$comment, %args});
	
	HTTP::WebTestScript::Plugin::Form::clearCache();
	
	if (!$gResponse->is_success)
		{
                warn "Probably too many redirects\n" if ($gResponse->is_redirect);
		croak "Error for '".$gRequest->uri."', ",$gResponse->status_line unless $gAllowFailure;
		}
	
	# Run onResponse
	no strict 'refs';
	foreach (@gOnResponse)
		{
		my ($command,$args) = @$_{'command','args'};
		#vverbose 0,$command,join(",",@$args),"\n";
		&$command(@$args);
		}
	use strict 'refs';
	
	return $gResponse;
	}

sub saveHTML
	{
	# only save this response, not chain of redirects etc.
	my ($request,$response) = @_;
	
	return if !$response->is_success;
	return if !$gLog;
	
	my $url = $request->uri;
	
	$url .= ".html" if $url !~ /\.(html)|(htm)$/i;
	#$url =~ s/([><|?&'"\/ ])/poundEncode($&)/eg;
	$url =~ s/([^a-zA-Z0-9_.-])/poundEncode($&)/eg;
	
	$gLog =~ s|/$||;
	my $htmlName = "$gLog/html_".timestamp()."_".sprintf('%.3d',$gSaveCt)."_".substr($url,0,200);
	my $fh = IO::File->new(">$htmlName") || die "Can't open output $htmlName, $!";
	
	print $fh $response->content;
	
	$fh->close;
	
	$gSaveCt++;
	
	return $htmlName;
	}

sub poundEncode
	{
	my ($char) = @_;
	
	return sprintf("#%.2X",ord($char));
	}
			

=head1 step description

Mark the beginning of a section 

=cut

sub step
	{
	my ($name) = @_;
	
	trace(1,step=>{description=>$name});
	}
	

=pod

=head1 name 'descriptive text'

Names the test for purposes of the log

Can't be a target from command line. Do this instead:

sub myTestName
	{
	steps....
	}

name 'My Test Name'
myTestName();

Now you can refer to it from the command line under 'myTestName'

=cut

sub name
	{
	my ($name) = @_;
	
	$HTTP::WebTestScript::Log::gDepth = "";
	trace(1,name=>{description=>$name},undef,$gNameIsOpen ? "closePrevious" : "leaveOpen");
	$HTTP::WebTestScript::Log::gDepth = "\t";
	$gNameIsOpen = 1;
	
	$gCurrentTest{'name'} = $name;
	}

sub timestamp
	{
	return $gTimestamp if $gTimestamp;
	
	my @t = localtime();
	$gTimestamp = sprintf("%4d%.2d%.2d_%.2d%.2d%.2d_%d",$t[5]+1900,$t[4]+1,@t[3,2,1,0],$$);
	
	return $gTimestamp;
	}

=head1 clickLink 'description', name=>'link name', id=>'id value', text=>'text or regex', href='text/regex'

Find a link (<a>), and GET the result (see "get").

The arguments are optional. Each is tested if present.

See notes in Verify for regexes.

=cut

sub clickLink
	{
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my (%args) = @_;
	croak "No NAME/TEXT/HREF supplied" if scalar(keys %args) <1;
	my ($name, $text, $href, $id) =delete @args{qw(name text href id)};
	croak "Unknown arguments: '",join("','",keys %args),"'" if scalar(keys %args);

	# 0=>tag 1=>{attrib=>x, ...}
	my $tag = findTag($HTTP::WebTestScript::gResponse, "a", 
		href=>$href,name=>$name, text=>$text, id=>$id);

	trace( ($tag ? 1 : 0),
		clickLink=>{description=>$comment,name=>$name,text=>$text,
			href=>$href, id=>$id,
			($tag ? () : (failed=>"not found"))
		});	
		
	if (!$tag)
		{
		croak "No link '".join("','",$name,$text,$href)."' found";
		}

	my $url = $tag->[1]->{'href'};

	HTTP::WebTestScript::_get(command=>'clickLink',url=>$url, description=>$comment,
		method=>'GET', base => $gResponse->base);	
	}

=head1 extract "description", element=>'tagName', [all=>1,] [emptyOK=>1,] text=>"some text", someAttribute=>'some value'

Finds the (first) element with the tagName which has the attributes and text with the 
specified values. if "all=>1' is specified, all tags are returned in an array-ref. If 
"emptyOK=>1" is specified, then not finding the element(s) is not an error.

The attributes and text are optional.

Returns a hash: 

 {tag=>"tagName", attributes=>{ attr1=>'value',...}, text=>'text till close tag'}

Note that the text will be empty if the tag is an empty (xhtml) tag.


=head1 extract "description", type=>'select|text|hidden|checkbox|radio|file|etc.', [all=>1,] someAttribute=>'some value', fromForm=>1, debug=>0|1

If you specify fromForm=>1, you need to specify the 'type' and 'name'. You'll get back different info (which includes info on the whole form):

Supplying debug=>1 will display each element (of type), with a clue about it's $someAttribute.

{value => $value, form => $form, name => $realName, $anAttribute=>$aValue...}
where 

	$form = { fields => {$name => $asAbove ...}, name=>$nameOrAction, method=>$method, action=>$action }
	$name = uc($type) . "_" . $realName # E.g. TEXT_username

If the element is a SELECT, then $value will be {$optionValue => $theText ...}, and one of the attributes should be selected=>$trueFalse.

With all=>1, you get a list of the above.

=cut

sub extract
	{
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my (%args) = @_;
	my ($fromForm) = delete $args{'fromForm'};
	my ($emptyOK) = delete $args{'emptyOK'};
	return HTTP::WebTestScript::Plugin::Form::extractFromForm($comment,@_)
		if $fromForm;

	croak "No ELEMENT supplied" if scalar(keys %args) <1;
	my ($element) =delete @args{qw(element)};

	# 0=>tag 1=>{attrib=>x, ...}
	my $tag = findTag($HTTP::WebTestScript::gResponse, $element,%args);
	trace($tag ? 1 : ($emptyOK ? 1 : 0),
		extract=>{description=>$comment,element=>$element,%args,
			$tag ? () : (failed=>"not found")
		});	

	if (!$tag && !$emptyOK)
		{
		croak "No element '$element' found (where ",join(",",%args),")";
		}

        if (!$tag)
            {
            return undef;
            }
	elsif (ref($tag->[0]) eq 'ARRAY')
		{
		my @changeStructure = map {{tag=>$_->[0], attributes=>$_->[1], text=>$_->[2]}} @$tag;
		return \@changeStructure;
		}
	else
		{
		return {tag=>$tag->[0], attributes=>$tag->[1], text=>$tag->[2]};
		}
	}
	
sub findTag
	{
	# takes text=>"xxx","attr"=>"xxx", ... as args
	# matches against the text (up to end tag, collapsed) & each attribute
	# returns the tag ["tagName",{attributes},"text"]
	my ($response, $tagName, %args) = @_;
	my ($extractAll) = delete $args{'all'};
	my ($debug) = delete $args{'debug'};
	my $textPattern;
	$textPattern = delete $args{'text'} if (exists $args{'text'} && defined $args{'text'});
	
        confess "no response object" if !$response;
	my $parser = HTML::TokeParser->new($response->content_ref);
	
        if ($debug) {vverbose 0,"Find <$tagName> ...\n"};
	my @collectedResults; # only if $extractAll
        my $targetTagName = ref($tagName) eq 'Regexp' ? [] : [$tagName];
	while (my $tag = $parser->get_tag( @$targetTagName )) # list can go in here
		{
                next if $tag->[0] =~ /^\//; # covers end-tag case
                next if !$targetTagName && $tag->[0] !~ $tagName;
		my $found = 1;
		# use Data::Dumper; vverbose 0,"\ttry tag ",Dumper($tag->[1]),"\n";

                my $attr = $tag->[1];

                # fix xhtml empty tag greediness
                my $lastAttrib = $tag->[2][-1];
                if ($lastAttrib =~ m|/$|) {
                    $attr->{$`} = ($attr->{$lastAttrib} eq $lastAttrib) ? $` : $attr->{ $lastAttrib};
                    delete $attr->{ $lastAttrib };
                    $tag->[2][-1] = $`;
                    }
		
		# all attributes
		while (my ($attribute,$value) = each %args)
			{
			if (defined $value)
				{
				$found &= isTagByAttribute($tag,$attribute=>$value,$debug);
				next if !$found;
				}
			}
		next if !$found;

		# text (bug: an empty xhtml tag bollixes up tokeparser here)
		my $text = (exists $tag->[1]->{'/'}) ? "" : $parser->get_trimmed_text("/".$tag->[0]);	
                # parser also introduces spurious garbage
                $text =~ s/^$SpuriousText//;
                $text =~ s/$SpuriousText$//;
                $text =~ s/$SpuriousText+/ /g;

		# vverbose 0,"\t'",$text,"'\n";

		if (defined $textPattern)
			{
			$found &= isTagByText($text,$tag,$textPattern);
			}
		next if !$found;

		if ($found)
			{	
			$tag->[2] = $text;
			if ($extractAll)
				{
				push @collectedResults,$tag;
				next;
				}
			else
				{
				return $tag;
				}
			}		
		}

	return \@collectedResults if scalar(@collectedResults);
	return undef;
	}

sub isTagByText
	{
	# up to end tag!
	my ($text, $tag,$textPattern) = @_;
				
	vverbose 10,"try <".$tag->[0]."> by text=>'$textPattern'\n";

	#vverbose 6,"text: '$text'\n";
	
	if (defined $textPattern)
		{
		return 
			ref($textPattern) eq 'Regexp'
			? $text =~ $textPattern
			: $text eq $textPattern
			;
		}
	else
		{
		return 0;
		}
	}	
	
sub isTagByAttribute
	{
	my ($tag,$attribute,$value,$debug) = @_;
				
	vverbose 10,"try <".$tag->[0]."> by $attribute=>'$value'\n";

	my $attr = $tag->[1];
	if ($debug) 
            {
            my $tagsAttribute = 
                $attribute."="
                .(exists($attr->{$attribute}) 
                    ? ('"'.$attr->{$attribute}.'"')
                    : "n/a");
            vverbose 0,"try <".$tag->[0]." ".$tagsAttribute."> by $attribute=>'$value'\n";
            }

	if (exists $attr->{$attribute})
		{
		return 
			ref($value) eq 'Regexp'
			? $attr->{$attribute} =~ $value
			: $attr->{$attribute} eq $value
			;
		}
	else
		{
		return 0;
		}
	}

=head1 forgetCookies

Forgets all cookies. The only other session-state might be encoded in urls in the html.

=cut

sub forgetCookies
	{
	my ($comment) = @_;

	$_UA && $_UA->cookie_jar(HTTP::Cookies->new());
	
	trace(1,forgetCookies=>{description=>$comment});
	}

=head1 onResponse 'command', itsArgs...

Register a command that should be executed for the response from each get/post. Useful for detecting generic run-time errors. For example:

onResponse 'verify', 'PHP Parse Error', not=>1, text=>'Parse error':

=cut

sub onResponse
	{
	my ($command,@args) = @_;
	
	push @gOnResponse , {command => $command, args=>\@args};
	}

=head1 perl -mHTTP::WebTestScript -e CLI_CreatePod

Create the WebTestScript.pod which aggregates all the separate files

=cut

sub main::CLI_CreatePod
	{
print	`perldoc -u WebTestScript.pm > WebTestScript.pod && ( find WebTestScript/ -name '*.pm' | xargs -n 1 perldoc -u ) >> WebTestScript.pod`;
	}

END 
	{
	print "\n";
	if ($gNameIsOpen)
		{
		my $LOG = getLog();
		print $LOG "</name>\n";
		}
	
	closeLog();
	}

# Our own useragent class because of a bug in LWP
package HTTP::WebTestScript::UserAgent;
use base qw(LWP::UserAgent);

# On redirect, do not send "old" content (i.e. post data)
sub redirect_ok
	{
	my $self = shift;
	my ($prospective_request) = @_;

	${$prospective_request->content_ref} = '';
	$prospective_request->content_length(0);
	return $self->SUPER::redirect_ok(@_);
	}

1;

__END__
# Tests
=head1 testing this package

perl -mUnitTestInLine -e UnitTestInLine::run thisFile.pm

=cut
=test setup
	Not a test, just get resources we need & define subs
		use HTTP::WebTestScript;

		our @cleanup;
		
		sub makeTestFile
			{
			# create a test file
			my $file = 'webtestscript.'.$$;
			my $path = "/tmp/$file";
			
			my $FH = IO::File->new(">$path") || die "can't make $path, $!";
			
			$FH->close;
			push @cleanup, sub {unlink $path};
			
			return ("file://$path","file:///tmp","$file");
			}
		
		END {map {&$_()} @cleanup}
					
=test relativeUrls
	Test hw_baseurl vs. absolute
		assertFalse("'file': is not supported by http::request/lwp") || die;
		
		hw_baseurl  "/";
		my ($absUrl, $baseUrl, $relativeUrl) = makeTestFile();
		assertNoDie(get $absUrl);

=cut
