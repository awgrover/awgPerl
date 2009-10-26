package Test::Website;
use strict; use warnings; no warnings 'uninitialized';

=head1 Name

Test::Website - Handier web-interaction for testing or scripting.

=head1 Synopsis

A concise set of commands for interacting with web-sites, and testing them (works with L<Test::Builder>). 
The DSL strives for DWIM'ness, and emphasizes simple matching expressions. 

The commands are like the interaction you would have with a web-page: "get" an url, "set" a form-field, "submit" a form, etc. Also, checking for elements/text.

    use Test::Simple;  # or Test::More etc.
    use Test::Website;

    baseurl 'http://google.com';

    get;
    element 'title', text => 'Google';
    set q => "Rakudo";
    submit;
    element text => qr/rakudo.org/; # fails! got 403
    my $link = element 'a', text => qr/Rakudo.org/;
    print "Will link to ".$link->attr('href')."\n";
    follow $link;

Most of the commands _are_ tests. E.g. "element" will fail if there is no such element. So, we play well
with all the L<Test::More> and related modules (e.g. L<Test::Behaviour::Spec>).

Note that this package recognizes HTML and XML pages. Obviously, form type interactions with XML pages may not make sense.

Other CPAN modules (L</"See Also">) have various approaches to testing/interaction with web-sites.

=cut

use Verbose; $kVerbose= $ENV{'VERBOSE'} || 0;

use base qw(Exporter);
our @EXPORT    = qw(
        baseurl
        save_html
        fail_on
        basic_auth
	get
	forget_cookies
        %BasicAuth
	); 

use HTTP::Request;
use HTTP::Request::Common;
use LWP::UserAgent;
use URI;
use IO::File;
use Carp;
use HTTP::Cookies;
use Data::Dumper;
use Memoize;

=head1 State variables

=head2 $Test::Website::Response

This is a L<HTTP::Response> object. It holds the last response, whether from a get or post.

=over

Hint: $Response->previous is defined if there was a redirect.

=back

=cut

# these need to occur before modules that might import them
# for use by internal procs. Cleared on get/post.
our (
    %PageCache,
    $Response
    );

use Test::Website::Element;
	push @EXPORT, @Test::Website::Element::EXPORT;
use import qw(&Test::Website::Element::_element);

use Test::Website::Form;
	push @EXPORT, @Test::Website::Form::EXPORT;

use Test::Website::Log;
our %BasicAuth; # username=>password

=head2 $Test::Website::Request

This is a L<HTTP::Request> object. It holds the last request, whether from a get or post.

=cut

our (
        $Save_html,
	$gBaseUrl, 
	$Request, 
	$_UA, 
	%gCurrentTest,
	$gTimestamp,
	$gSaveCt,
	$gNameIsOpen,
	@gOnResponse,
        $gAllowFailure, # don't die on ! success
	);


$gSaveCt = 0;

=head2 Test::Website::UA()

The LWP::UserAgent, with a slight tweak: "On redirect, do not re-send post-data."

A singleton.

=cut

sub UA
	{
	return $_UA if $_UA;
	
	$_UA = Test::Website::UserAgent->new(cookie_jar=>HTTP::Cookies->new());
	push @{ $_UA->requests_redirectable }, 'POST';
	return $_UA;
	}

=head1 Configuration

=head2 use Test::Website;

All the commands are imported into your module. Our functionality is actually split
into multiple modules, but all the commands are aggregated into a top-level import.

You'll need L<Crypt::SSLeay> to do https.

=cut

=head2 baseurl 'some-absolute-url'

The baseurl is convenient so you can use relative urls. This only affects "get", and you can
always provide an absolute url in "get".

=cut

sub baseurl
	{
	# set the base url for relative urls
	($gBaseUrl) = @_;
	}

=head2 fail_on "why", <element-predicates>

Needs a better name. This is really "elements that must NOT be on a page."

When a new response is obtained, each "fail_on" is tested, and causes a failure if it matches.

See L</"Element Predicates"> below.

    fail_on "PHP Warning notice", text => qr/Notice: /;

=cut

sub fail_on {
    my $comment = shift;
    croak "Need even number of args for hash. Did you forget the leading comment?" if @_ %2;
    push @gOnResponse, [ $comment, [@_] ];
    }

=head2 save_html "directory"

Response content will be saved in the directory, with a file-name mangled from the url. By
default, nothing is saved.

=cut

sub save_html {
    ($Save_html) = @_;
    $Save_html =~ s|/$||;
    croak "Directory for saving html ($Save_html) doesn't exist" if !-d $Save_html;
    }

=head2 basic_auth "name" => "password";

Set the username/password for basic auth. This sticks through subsequent requests.

To remove the basic auth user/pass:

    basic_auth;

=cut

sub basic_auth {
    croak "Expected username => password for basic_auth" if @_ != 2 && @_ != 0;
    %BasicAuth = @_;
    }

=head1 Requests

These commands function as tests, logging ok/fail for the relevant element (e.g. no <form>, <input> etc.).
as tests.

=head2 forget_cookies

Forgets all cookies. The only other session-state might be encoded in urls in the html.

=cut

sub forget_cookies
	{
	my ($comment) = @_;

	$_UA && $_UA->cookie_jar(HTTP::Cookies->new());
	
	trace(1,forget_cookies=>{description=>$comment});
	}

=head2 get "url"

Fetches the absolute or relative url. If L<save_html|/"save_html directory"> is on, saves to that directory (under the url name).

Returns the L<HTTP::Response>. Sets L<$Request|/_test__request>, L<$Response|/_test__response>;

The url is optional if you have a L<base_url|/baseurl__someabsoluteurl_>. That's convenient for getting the "home" page.

    base_url 'http://google.com';
    get;

Dies on !$Response->is_success;

=head2 get \*FILEHANDLE

A hack to that lets you use an open file-handle as the http response stream (headers, newline, body).

Obviously, trying to follow or post, or any other HTTP protocol things won't work.

I use this to test the module, stubbing (via L<Sub::Override>) the HTTP parts.

=cut

sub get
	{
	my ($url) = @_;
	
	_get(command=>'get',url=>$url,method=>'get',base=>$gBaseUrl);
	}
	
sub _get
	{
	my (%args) = @_;
	my ($command,$url,$method,$params, $comment, $base, $fileUpload, $debug) = delete @args{qw(command url method params comment base fileUpload debug)};

        local $Test::Builder::Level = $Test::Builder::Level + 1;

	$method = 'GET' if !defined $method;
	$method = uc($method);

        %PageCache = ();

	croak "URL was empty for $command" if !$url && $method eq 'GET' && !$gBaseUrl;
	# warn "##url ".$url;
	
        # vverbose 0,"url->abs, using base=$base, resp->base=".( $Response ? $Response->base : '') . ", gbaseurl=$gBaseUrl";
        # vverbose 0,"Will use base: ".($base || ( $Response ? $Response->base : $gBaseUrl) || "http://");
        # allow a form to have no/empty action
        # vverbose 0,"url $url";
	my $uri;
        if ($method eq 'POST' && $Response && $url eq '') {
            $uri = $Response->request->uri->clone;
            $uri->query(undef);
            }
        else {
            if (ref($url) eq 'GLOB' || ref($url) eq 'IO::File') {
                $uri = URI->new("file://");
                }
            else {
                $uri = URI->new_abs($url,
                    $base || ( $Response ? $Response->base : $gBaseUrl) || "http://");
                if ($ENV{'NOFETCH'}) {
                    ($uri,$url) = fileViaNOFETCH($url);
                    }
                }
            }
        # vverbose 0,"Used $uri (where request was ".($Response ? $Response->request->uri : "no response object").") for POST" if $method eq 'POST';
	#vverbose 0,"$uri fileUpload? $fileUpload\n";
	#vverbose 0,"args ",join(",",%args),"\n";
	vverbose 2,"Will $method ".$uri->as_string." with params ",Dumper($params),"\n"; use Data::Dumper;

        my $header = HTTP::Headers->new();
        if (keys(%BasicAuth)) {
            $header->authorization_basic(%BasicAuth);
            }

	if ($method eq 'GET') {
                vverbose(1,"setting form...");
                $uri->query_form(ref($params) eq "HASH" ? %$params : @$params) if ($params);
		$Request = HTTP::Request->new(GET => $uri, $header);
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
                vverbose 4,"params ".Dumper($params);
		$Request = POST($uri,$params, @headers, $fileUpload ? (Content_Type=>'form-data') : ());
		}
	else
		{
		die "Unknown method '$method'";
		}
		
	die "Content\n",$Request->content,"\n " if $debug;
        vverbose(1,$method."ing $url...");

        # all the GLOB stuff is the "get \*FH" hack stuff
        if (ref($url) eq 'GLOB' || ref($url) eq 'IO::File') {
            $Response = HTTP::Response->parse(join "",<$url>);
            $Response->code(200);
            $Response->request($Request);
            }
        else {
            croak "Trying to $method '$url' as $uri despite \$ENV{'NOFETCH'}" if $ENV{'NOFETCH'};
            $Response = UA->request($Request);
            }
	
        vverbose(1,"save file... ".$Response->status_line);
	my @size = ($Response->is_success) ? (bytes=>length($Response->content)) : ();
	my @content = ($Response->is_success) ? () : (content=>$Response->status_line);
	
	my $savedFile = _saveHTML($Request,$Response);
	my @saved = $savedFile ? (savedfile=>$savedFile) : ();
	
	trace($Response->is_success,
		$command=>{method=>$method, uri=>$uri->as_string,
			http_status=>$Response->code,@content, @size, @saved,
			%args},
                $Response->is_success ? (because => "not is_success") : (),
                because => 'get '.$Response->code
                );
	
	if (!$Response->is_success)
		{
                warn "Probably too many redirects\n" if ($Response->is_redirect);
		# croak "Error for '".$Request->uri."', ",$Response->status_line unless $gAllowFailure;
                return $Response;
		}
	
	# Run onResponse
	no strict 'refs';
	foreach (@gOnResponse)
            {
            my ($comment, $args) = @$_;
            my $res = _element(@$args);

            if ($res) {
                trace(($res ? 0 : 1), 'fail_on' => $args, because => $comment);
                }
            }
        trace(1, 'fail_on' => { passed => scalar(@gOnResponse) }) if scalar(@gOnResponse);

	use strict 'refs';
	
	return $Response;
	}

=head2 get and NOFETCH

You can cause Test::Website to use cached web-pages by setting the environment variable NOFETCH
to the name of a file containing a map.

Example:

    env NOFETCH=mapfile perl something-using-test-website

The "mapfile" is perl-code that has a last array-ref like this
    [
    ['arg to a get()' => 'filename of cached web-page'],
    [/regex matchine get()'s arg/ => 'filename of cached web-page'],
    ...
    ]

The cached web-page must have minimal http headers:

    HTTP/1.x 200 OK

    <html>....</html>

Add the mime-type to get xml parsing:

    HTTP/1.x 200 OK
    Content-Type: application/atom+xml; charset=UTF-8

    <someoutertag>...</someoutertag>

=cut

sub fileViaNOFETCH {
    my ($url) = @_;

    my $map = mapFromNOFETCH();
    my $filename;
    foreach my $entry (@$map) {
        if ((ref($entry->[0]) eq 'Regexp' && $url =~ $entry->[0]) || $entry->[0] eq $url) {
            $filename = $entry->[1];
            last;
            }
        }
    croak "Couldn't find a mapping of '$url' to filename in \$ENV{'NOFETCH'} (".$ENV{'NOFETCH'}.")" if !$filename;

    my $fh = IO::File->new("<$filename") || croak "Couldn't read '$filename' as cached result for url '$url', $!";
    my $uri = URI->new("file://$filename");
    return ($uri,$fh);
    }

memoize 'mapFromNOFETCH';
sub mapFromNOFETCH {
    my $mapfile = $ENV{'NOFETCH'};
    die "expected \$ENV{'NOFETCH'} ($mapfile) to be a _file_ mapping urls to header/html file-names: [ [ url => file ] ]" if
        (! -f $mapfile || (-l $mapfile && ! -f (readlink $mapfile)));
    my $fh = IO::File->new("<$mapfile") || croak "Couldn't read \$ENV{'NOFETCH'} ($mapfile) cache list, $!";
    my $rez = eval( join("",<$fh>) );
    if ($@) {
        warn "In \$ENV{'NOFETCH'} ($mapfile):\n";
        die $@;
        }
    croak "Expected an array-ref from \$ENV{'NOFETCH'} ($mapfile) found a ".ref($rez) if ref($rez) ne 'ARRAY';
    return $rez;
    }

=head2 OtherRequestsGoesHere

=cut

sub _saveHTML
	{
	# only save this response, not chain of redirects etc.
	my ($request,$response) = @_;
	
	return if !$response->is_success;
	return if !$Save_html;
	
	my $url = $request->uri;
	
	$url .= ".html" if $url !~ /\.(html)|(htm)$/i;
	#$url =~ s/([><|?&'"\/ ])/poundEncode($&)/eg;
	$url =~ s/([^a-zA-Z0-9_.-])/poundEncode($&)/eg;
	
	my $htmlName = "$Save_html/html_".timestamp()."_".sprintf('%.3d',$gSaveCt)."_".substr($url,0,200);
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
			
sub timestamp
	{
	return $gTimestamp if $gTimestamp;
	
	my @t = localtime();
	$gTimestamp = sprintf("%4d%.2d%.2d_%.2d%.2d%.2d_%d",$t[5]+1900,$t[4]+1,@t[3,2,1,0],$$);
	
	return $gTimestamp;
	}


sub main::CLI_CreatePod
	{
print	`perldoc -u Website.pm > Website.pod && ( find Website/ -name '*.pm' | xargs -n 1 perldoc -u ) >> Website.pod`;
	}

END {
    print "\n";
    if ($gNameIsOpen) {
        my $LOG = getLog();
        print $LOG "</name>\n";
        }
    
    closeLog();
    }


# Our own useragent class because of a bug in LWP
package Test::Website::UserAgent;
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


=head1 Tests/Extraction

=head1 OtherTestsGoesHere

=head1 Fixme

Move the pagecache to the response object.

Remove the use of pagecache for form-info.

headers?

=head1 Limitations

Does not run javascript. So, you can't test it. Suggestions/implementation/proposals on implementing this are welcome.

Does not load any images, css, or other media.

Doesn't know about CSS syntax. You could do textual checking.

=head1 See Also

=over

=item * L<HTML::TreeBuilder>/L<HTML::TreeBuilder::XPath>. How we parse and search the web-page.

=item L<Test::Builder> and its ecosystem. Framework, and commands for test suites.

=item * L<WWW::Mechanize>. Another web interaction tool: OO, lower-level, better scraping.

=item * L<Test::HTTP>. Another web testing tool: OO, not tree parsing, simple, Test::Builder based.

=item * L<Test::HTTP::Syntax>. Another web testing tool, built on Test::HTTP. Specify the test as a http-stream exemplar (not programmatic).

=item * L<http://seleniumhq.org/>. Test and excersize web-sites _in_ your browser.

=item * L<http://www.webinject.org/>. XML-spec for testing.

=item * L<Test::XML>. Diff for XML.

=item * The Ruby ecosystem.

=item * And more L<http://www.softwareqatest.com/qatweb1.html#FUNC>, L<http://perl-qa.hexten.net/wiki/index.php/TestingTools>, 

=item * L<curl> or L<wget>. Command line web-site interaction, spidering.

=back

=head1 TODO

clean up trace for logging of a trace.

add no-TAP to inhibit test messages

add no-die

how to get working with test::behavior

=head1 Creating the POD

To assemble the POD for Test::Website,

    cd ..../Test
    make -f Website/Makefile pod

=cut
