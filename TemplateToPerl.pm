package TemplateToPerl;
use base qw(Class::New);

# copyright 2004,2005 Alan Grover (Baltimore)

=pod

=head1 Summary

A template rendering system based on the principles of: 

	pull: the template decides which data is needed
	no-code in template: no perl mixed in HTML
	minimal tags: logic & complexity are in object methods.
	slot paths: "variables" can be catenated methods, etc.

=head1 Usage
	
	my %datapool;
	
	# setup some slots in the datapool. These values can be used
	# by the template
	
	$datapool{'someslotname'} = $someValue;

	# Make the template-processor
	my $newHTML = TemplateToPerl->new
		(datapool=>\%datapool, filename=>$templateName);
	
	# Get the output
	print $newHTML->output;


	<html> ...
		<body>
			...
			Thanks for ordering {{$someslotname}} from us!
		</body>
	</html>

=head1 Methods

=head2 new

=head3 datapool => $hashRef

The data/objects that the template may use. See slots below.

=head3 filename => $filenameOrGlob || text => $string

Supply the template as a filename (relative to cwd, or absolute), a reference to a filehandle,
or as a string.

=head2 output

The output after processing the template, as string.

=head1 Slots

A slot is a expression starting with a key in the datapool, that draws data from the datapool.

Slots start with "$", followed by a key in the datapool hash. 

The slot can be a "path" through the data structure, using steps like ".somekey".

Examples:

	{{$password}}	# interpolated as $datapool->{'password'}
	{{$aHash.bob}}	# as $datapool->{'aHash'}->{'bob'}
	{{$anArray.4}} # as $datapool->{'anArray'}->[4]
	{{$anObject.something}} # as $datapool->{'anObject'}->something()
	{{$aSubRef}} # as &{ $datapool->{'aSubRef'} }()
	

It is up to you to put the right data/structures in the datapool.

A simple slot (just a key) will work whether it "exists" in the datapool or not. Paths
may cause an error, just as they would in perl: so $obj.method would fail if there was no
such method, but $hash.key would return undef if the key didn't exist.

=head2 Usage

Since this is a "pull" based system, you should think of your application as approximating a tree of data. The root of the tree is the datapool, each value in it is a branch, and the template pulls the values it wants. E.g.:

	{{$catalog.5678.price}}
	{{IF $session.user.privileges.isEditor}} ...

Of course, this is an approximation. For example, the slot 'config' is typically your app's configuration values, 'session' is the current session, etc.

=head2 Special slots

	$someArray.count  the number of elements in the array
	$xxx_index        the index of this iteration, where xxx is the name in the ITERATOR.

=head2 Lazy values

To avoid constructing a value when it might not be used, you can use a "lazy" value. Wrap the desired expression in a "sub":

	$myDatapool->{'catalog'} = sub {My::Catalog->new};

The "new" will only execute if the template needs it. So, if it is inside an if, it may not be executed and you can avoid the overhead.

=head2 Memo'izing

The slots are memo'ized so they don't change during the course of the template, and functions/methods are only called once.

You should not be able to change the value of a slot during a template. So, even if you have a function that causes side-effects,
those side-effects won't show up in slots that have already been used. Of course, it will affect slots that haven't been used yet 
(textually later in the template).

You can also rely on side-effects only happening once (during the template). Note that memo'izing is by it's slot-path. So, the slot
$a.b.c is memo'ized, but if you contrive some other way to access 'c', it will be called again.

You could 'memoize' a method yourself to ensure it is only calculated once (see 'man memoize'). E.g.

	use Memoize;
	
	memoize 'myDBAccess';
	sub myDBAccess
		{
		my $db = DBI->new(...);
		my $rows = $db->fetch_array("select something");
		return $rows;
		}

Caution: If you are using a "persistent" perl (e.g. modperl), you will need to clear the memo'izing at the end of the http request

	END {
	unmemoize 'myDBAccess';
	}

Test to make sure it is unmemo'izing!

=head1 UnitTests

This module has internal unit-tests.

	perl -mUnitTestInLine -e UnitTestInLine::run TemplateToPerl.pm

(cd to the directory, that containts this TemplateToPerl.pm, somewhere in your PERL5LIB)

See 'perldoc UnitTestInLine'

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use Verbose;
$kVerbose=0;

use Carp;
use CGI;
use Memoize;

use TemplateCompiler::Parse;

our $gXSLProcessor = 'xsltproc --nonet --nowrite --novalid';

use Class::MethodMaker get_set=>[qw(filename datapool text line parser
	interpolateCache perlCode trimFinalEOL)];

sub preInit
	{
	my $self=shift;
	
	$self->line(1);
	$self->interpolateCache({});
	
	return $self->SUPER::preInit(@_);	
	}
		
sub init
	{
	my $self=shift;
	
	die TemplateCompiler::NewException->new(message=>"Datapool must be a hashref")
		if (defined ($self->datapool) && ref($self->datapool) ne 'HASH');		
	
	return $self->SUPER::init(@_);
	}
	
sub output
	{
	# Given the CGI, datapool and some HTML,
	# do the substitutions and return the fixed up HTML
	# do a perldoc on this file for usage in html
	
	my $self = shift;
	
	my ($datapool) =
		($self->datapool);
	die "sanity: no templateName" if !$self->text && !$self->filename;
	
	my $fullTemplateName = $self->filename;
	 if (! ref($self->filename)) # handles are GLOB (or IO::File?)
	 	{
		$self->filename =~ /(.*)/;
		my ($fullTemplateName) = $1;

		die TemplateCompile::NoTemplateException->new(filename=>$fullTemplateName)
			if $fullTemplateName && !-f $fullTemplateName;
		}

	vverbose 2,"template: '".($fullTemplateName || text)."'\n";
	
	my $taintedHtml;
	if ($self->text)
		{
		$taintedHtml = $self->text;
		}
	elsif (ref $fullTemplateName)
		{
		$taintedHtml = join("", <$fullTemplateName>);
		chomp $taintedHtml if $self->trimFinalEOL;
		}
	else
		{
		$taintedHtml = $self->readTemplate($fullTemplateName);
		}

	$self->perlCode( $self->createPerlCode($taintedHtml, $fullTemplateName) );
	#vverbose 0,"CODE\n",$self->perlCode(),"---\n";	

	my $rendered = $self->evalOrDieWithFixup ($self->perlCode);	# FIXME: cache as subroutine code?

	#vverbose 0,"## HTML\n$rendered\n";
	
#	my @keys = grep {$_ =~ /itor/} keys %{$self->interpolateCache}; 
#	my $firstKey = $key[0];
	
	#vverbose 0,"memoized: ",join(",",map {"$_=>$self->interpolateCache->{$_} "} @keys),"\n";
	
	return $rendered;
	}

sub readTemplate
	{
	my $self=shift;
	my ($filename) = @_;
	my $fh = IO::File->new("<$filename") || die "Can't read $filename, $!";
	return join("",<$fh>);
	}

sub createPerlCode
	{
	# FIXME: factor this file into the compiler & the helper
	# FIXME: then, make it polymorphic for the compiler (some new arg = perl/scheme) 
	my $self=shift;
	my ($taintedHtml, $fullTemplateName) = @_;
	
	my $parser = TemplateCompiler::Parse->new(string=>$taintedHtml,provenance=>$fullTemplateName);
	$parser->parse;
	$self->parser($parser);
	
	my @fixedChunks = @{$parser->result};
	my $unsafePerlCode = join(".",@fixedChunks);	# FIXME: cache this
	my ($perlCode) = $unsafePerlCode =~ /(.*)/s;
	vverbose 3,"## PERL\n$perlCode\n";
	
	return $perlCode;
	}
	
sub evalOrDieWithFixup
	{
	my $self=shift; # required in the perlCode we are evaluating
	# figure out current "eval" number
	eval 'die'; # must be a string!
	my ($num) = $@ =~ /\(eval (\d+)\)/;
	$num++;

	my $rez = eval $_[0];

	if ($@)
		{
		my $line = (caller(1))[2];
		my $file = (caller(1))[1];

		my $rep = $self->parser->provenance
			? $self->parser->provenance
			: "(internal error in compiled form of text during $file at line $line)"
			;

		$@ =~ s/\(eval $num\)/$rep/;
		die $@;
		}

	return $rez;
	}
		
sub _iterate
	{
	# called by perl'ified template to iterate over some HTML
	my $self=shift;
	my ($fileName,$line,$iterable,$itorName,$perlSub) = @_;
	
	#vverbose 0,"Iterate '$iterable'  as $itorName\n";
	
	my @each;
	my $idx = 0;
	my $wasDPIndex = $self->datapool->{$itorName."_index"};
	foreach my $element (@$iterable)
		{
		$self->datapool->{$itorName} = $element;
		$self->datapool->{$itorName."_index"} = $idx;
		
		# un-memoize this slot's lookup
		# NB: doesn't seem to work if your put the RE in the grep directly
		my $key = qr/^$self\.$itorName/;
		my @itorKeys = grep { $key } keys %{$self->interpolateCache};
		#vverbose 0,"delete keys '$key' ",join(",",@itorKeys),"\n";
		#vverbose 0,"keys ",join(",",keys %{$self->interpolateCache}),"\n";
		delete @{$self->interpolateCache}{@itorKeys};
		
		push @each, &$perlSub();
		$idx++;
		}
	$self->datapool->{$itorName."_index"} = $wasDPIndex;
	return join "",@each;
	}
	

sub _interpolateQStringEncode
	{
	my $rez = CGI->escapeHTML(shift->interpolate(@_));
	my $hexify = sub
		{
		sprintf "&#%X;",ord($_[0]);
		};
		
	$rez =~ s/([' =#@%+'])/&$hexify($1)/eg;
	return $rez;
	}

sub _interpolate
	{
	return CGI->escapeHTML(shift->interpolate(@_));
	}

sub _interpolateRaw
	{
	return shift->interpolate(@_);
	}

sub interpolate
	{
	my $self=shift;
	my ($fileName,$line,$expression) = (shift,shift,shift);
	# rest of @_ is the elements of the slot-path
	
	# couldn't get memoize to work with a normalizer
	my $key=join(".",$self,@_);
	return $self->interpolateCache->{$key} if exists $self->interpolateCache->{$key};
	
	my $current = $self->datapool;
	
	vverbose 8,"Try $expression via '".join("','",@_),"'\n";
	foreach (@_)
		{
		vverbose 8,"\t$current.$_\n";
		if (!defined $current)
			{
			die TemplateCompile::SlotException->new(
				expression => $expression,
				location => $_,
				message => "can't call '$_' on undef",
				fileName => $fileName,
				line => $line,
				)
			}
	
		if (!ref $current)
			{
			die TemplateCompile::SlotException->new(
				expression => $expression,
				location => $_,
				message => "can't call '$_' on scalar ('$current')",
				fileName => $fileName,
				line => $line,
				)
			}
		
		if (ref $current eq 'ARRAY')
			{
			$current = $_ eq 'count'
				? scalar(@$current)
				: $current->[$_];
			}
		elsif (ref $current eq 'HASH')
			{
			$current = $current->{$_};
			}
		else
			{
			if ($current->can($_))
				{
				$current = $current->$_();
				}
			else
				{
				die TemplateCompile::SlotException->new(
					expression => $expression,
					location => $_,
					message => "no method ".ref($current)."->$_",
					fileName => $fileName,
					line => $line,
					)
				}
			}	
		
		# And resolve a sub{}
		if (ref $current eq 'CODE')
			{
			eval {$current = &$current()};
			if ($@)
				{	
				my $thrown=$@;
				die TemplateCompile::SlotException->new(
					expression => $expression,
					location => $_,
					message => "error during $_(), $thrown",
					fileName => $fileName,
					line => $line,
					)
				}
			}
		vverbose 8,"\t\t=>$current\n";
		}
	$self->interpolateCache->{$key} = $current;
	return $current;
	}

sub _include
	{
	my $self=shift;
	my ($protocol, $filename, $xpath, $xsl) = @_;

	# FIXME: check for path outside permitted values (absolute, etc.)
	vverbose 0,"include '$xpath' from '$filename' as '$xsl'\n";

	if (!-r $filename)
		{
		die TemplateCompiler::NoTemplateException->new(filename=>$filename);
		}

	# build up a pipeline for xsl (if necessary)
	my @clauses;

	my ($xpathXSL,$aClause) = $self->applyXPath($filename, $xpath, $xsl ? 1 : 0);
	push @clauses, $aClause if $aClause;

	push @clauses, "cat \"$filename\"" if $xsl && !$xpath;
	push @clauses, $self->applyXSL($xsl);

	my $pipeline = join("|", grep {$_} @clauses);
	vverbose 0,"pipe: $pipeline\n";
	
	my $pipeSource;
	if ($pipeline)
		{
		my $sink;
		use IPC::Open2;
		my $pid = open2($pipeSource,$sink, $pipeline);
		print $sink $xpathXSL;
		close $sink;
		}
	
	my $newHTML = TemplateToPerl->new(
		datapool => $self->datapool,
		filename => $pipeSource || $filename,
		interpolateCache => $self->interpolateCache,
		trimFinalEOL => $pipeSource ? 1 : 0,
		);

	return $newHTML->output;
	}

sub applyXSL
	{
	my $self=shift;
	my ($xslFile) = @_;

	return undef if !$xslFile;
	return "$gXSLProcessor \"$xslFile\" -";
	}

sub applyXPath
	{
	# If there is more xsl processing, we need to wrap our output.
	# Otherwise, just do the xpath selection
	my $self=shift;
	my ($template,$xpath,$needsWrapping) = @_;

	return if !$xpath;

	my $body = '<xsl:apply-templates select='
		. '"'.CGI->escapeHTML($xpath) . '"/>'
		;
	my $xsl = <<'EOS';
<?xml version="1.0"?>
<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'>
EOS

	$xsl .= '<xsl:output omit-xml-declaration="yes"/>' if !$needsWrapping;

	$xsl .= '<xsl:template match="/">';

	$xsl .= $needsWrapping
		? '<xsl:apply-templates select="/*"/>'
		: $body;

	$xsl .= '</xsl:template>';

	$xsl .= 
		'<xsl:template match="/*"><xsl:copy>'
		. '<xsl:apply-templates select="@*"/>'
		.$body
		.'</xsl:copy></xsl:template>'
		if $needsWrapping;

	$xsl .= <<'EOS';
<xsl:template match="*">
	<xsl:copy>
	<xsl:apply-templates select="*|@*|text()"/>
	</xsl:copy>
</xsl:template>

<xsl:template match="@*|text()">
	<xsl:copy/>
</xsl:template>
</xsl:stylesheet>
EOS

	vverbose 0,$xsl,"\n";
	return ($xsl,"$gXSLProcessor - \"$template\"")
	}
1;
__END__	

=head1 Template Language

=head2 {{$slot}} 

Interpolates the value, as a string, and HTML escaped.

See @Slots above.

In the HTML, replace with the value of the slot, except in comments.

Nesting does work: For any part of a $slot, you should be able to put a {{$slot}}

	{{$slot.{{$bob}}.more}}.
	{{{{$decideARoot}}.name}}

The second would first interpolate to something like {{$someRoot.name}}.

=head2 {{{$slot}}} ...

Same, but escaped for use in query-strings (NB: not url-encoded)

Should just escape '=@#%+' in addition to normal HTML escaping.

=head2 {{{{$slot}}}}

Same, but no escaping. Ask yourself why you are doing this, it means you have HTML in your code (with the exception of proxied html).

=head2 {{IF expr}} true-body {{ELSE}} false-body {{/IF}}

If the expr is true, processes the true-body. Otherwise process the false-body.

The ELSE part is optional, in which case the false-body is empty.

False is 0 || undef || ''. True is anything else.

=head3 expr

An expression can be:

	$slot
	$slot eq 'a string'
	$slot eq 1234
	$slot eq $anotherSlot

You may put a "!" in front of the expr, which then means "not expr": {{IF ! expr}} ....

=head3 Example
	
		{{IF $product.outOfStock}}
			Sorry, out of stock
		{{/IF}}

=head2 {{ITERATE $slot $eachValue}} body  {{/ITERATE}}

Sets $eachValue to each value of $slot (assumes an arrayref), and processes the body. Thus, convenient for generating rows, lists, etc. Read as "iterate $slot as $eachValue".

	Ex:
		{{ITERATE $results $itor}}
			{{$itor.something}}<br>
		{{/ITERATE}}

You also get a special slot which is the index (counts from 0). The index-slot has the same name as the iterator slot, plus "_index":

	Ex:
		{{ITERATE $results $itor}}
			Index {{$itor_index}} is {{$itor.something}}<br>
		{{/ITERATE}}

Someday: You should be able to iterate over multiple collections:

	iterate c1 c2 i1 i2
		would assign i1=c1[0] && i2=c2[0] for the first loop
			and i1=c1[1] && i2=c2[1], for the next, etc.
			using undef for the short collection(s)
	iterate c1 c2 i1
		would alternate, i1=c1[0] for the first, 
			and i1=c1[1] for the second, etc.
	iterate c1 i1 i2
		would assign both for each loop:
			i1=c1[0] & i2=c1[1], etc.	

Someday: You should be able to iterate over hashes:

	iterate h1 k1
		would get the keys
	iterate h1 k1 v1
		would get each key and value
	Sort order?
	OR, would it work like above: you get values, and _index is the key?

=head2 Comments

Comments are completely elided, before processing, so slots aren't interpolated (nor called). NB: Comments are removed from the output!

=head2 Include: {{file:file-path}} or {{{{file:file-path}}}}

Processes the file as if it were a template, and interpolates the result. This is done with the current state of the datapool, which only makes a difference inside an iteration. So, an interation introduces a new slot into the datapool that the included file can use.

The '{{{{' version does not process the file, but HTML-encodes it and includes it.

The file-path can be relative (to the includePath attribute), or absolute. NB: An absolute path requires exactly one leading /, or exactly three leading /. The first is a convenience, the second is compatible with uri forms.


Example:

	Take the quiz:
	{{file:quiz.tmpl}}
	blah<pre>
	Check out our password file:
	{{{{file:/etc/passwd}}}}
	{{{{file:///var/log/messages}}}}</pre>

FIXME: should prevent recursion, if the datapool is identical.

FIXME: Add more protocols (standard uri protocols)

=head2 {{SELECT 'xpath-expr' FROM file:file-path}}

Uses an xsl transform to copy nodes from the xml file. Will fail if the file-path isn't an xml file, or if the xpath-expr is bad.

'file-path' is treated as above in Include.

The xpath-expr will be html-encoded, so you should be able to write it without entities.

NB: xpath-expr is applied within the root or document node, so you should specify an xpath expression that works from either. E.g.

	/*/a[@class="external"]
	or
	//a

NB: Similarly, if you want to select the document-node, you'll have to use an absolute xpath:

	/*

Remember, whitespace between xml tags will tend to get elided.

Uses xsltproc.

This constructs an xsl file like this (also, see below):

	<xsl:template match="/">
	<xsl:apply-templates select="your-xpath-expression-here"/>
	</xsl:template>

	...identity copy w/o comment/processing-instr...

and applies it to your xml file.

=head2 {{SELECT file:file-path-xml AS file:file-path-xsl}}

Applies an xsl transform on the xml file. Will fail if the file-path-xml/file-path-xsl isn't an xml file.

Treats the result as a template, so interpolations/etc. work.

=head2 {{SELECT 'xpath-expr' FROM file:file-path-xml AS file:file-path-xsl}}

Uses an xsl transform to copy nodes from the xml file, then apply the final xsl file. Will fail if the file-path-xml/file-path-xsl isn't an xml file, or if the xpath-expr is bad.

Note that file-path-xsl will be applied to a valid xml document. This is accomplished by keeping the original document-root when the xpath-expr is applied:

		<xsl:template match="/">
		<xsl:apply-templates select="/*"/>
		</xsl:template>
		
		<!-- copy the document-node (w/o text) & select nodes inside it -->
		<xsl:template match="/*">
			<xsl:copy>
				<xsl:apply-templates select="@*"/>
				<xsl:apply-templates select="/*/a[@b=&quot;bob&quot;]"/>
			</xsl:copy>
		</xsl:template>
		
		...identity copy...

=head3 Identity XSL transform

You can experiment/debug your xpath with this xsl file (substitute in your-xpath):

	<?xml version="1.0"?>
	<xsl:stylesheet version='1.0' xmlns:xsl='http://www.w3.org/1999/XSL/Transform'>
	<xsl:output omit-xml-declaration="yes"/>

	<!-- NB: if you do a full 'xpath-expr FROM xmlfile AS xslfile',
		replace this xsl:template with the stuff in that section -->

	<xsl:template match="/">
	<xsl:apply-templates select="your-xpath-here"/>
	</xsl:template>
	
	<!-- identity starts here -->
	<xsl:template match="*">
			<xsl:copy>
			<xsl:apply-templates select="*|@*|text()"/>
			</xsl:copy>
	</xsl:template>

	<xsl:template match="@*|text()">
			<xsl:copy/>
	</xsl:template>
	</xsl:stylesheet>

=head2 Including a literal {{ (or, escaping {{)

Use the html entities to include two or more {'s.

	&#123; means {

=cut
	
=begin in-line-test

=test interpolate
	Test slot-path interpolation
		my $obj = TemplateCompile::Exception->new(message=>'objValue');
		
		my %datapool = 
			(
			firstSlot => 'first',
			secondSlot => 'second',
			indirectSlot => 'key1',
			firstHash => {key1=>'value1', array => [ 'inner'] },
			firstObject => $obj,
			);
		my $input = '#{{$firstSlot}}# #{{$secondSlot}}#';
		my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#first# #second#",
			"Simple interpolate");
		
		$input = '#{{$firstHash.key1}}#';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#value1#",
			"Simple path interpolate");
		
		$input = '#{{$firstHash.array.0}}#';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#inner#",
			"Path interpolate");

		$input = '#{{$firstObject.message}}#';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#objValue#",
			"Object path interpolate");

		$input = '#{{$firstHash.{{$indirectSlot}}}}#';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#value1#",
			"Nested slot interpolation");

=test interpolate escaping
		my %text =
			(
			'first'=>['first','first'],
			'first>'=>['first&gt;','first%3E'],
			'first&'=>['first&amp;','first%26'],
			'first second'=>['first second','first%20second'],
			'first='=>['first=','first%3D'],
			);
		while (my ($string,$rez) = each (%text))
			{
			my %datapool = (a=>$string);
			my ($expected,$expectedUE) = @$rez;
			my $input = '#{{$a}}# #{{{$a}}}#';
			my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
				->output;
			assertEQ($rez,
				"#$expected# #$expectedUE#" ,
				"HTML Escape $string");
			}

		%text =
			(
			'first'=>['first','first'],
			'<first>'=>['&lt;first&gt;','<first>'],
			'first&'=>['first&amp;','first&'],
			'first second'=>['first second','first second'],
			'first='=>['first=','first='],
			);
		while (my ($string,$rez) = each (%text))
			{
			my %datapool = (a=>$string);
			my ($expected,$expectedUE) = @$rez;
			my $input = '#{{$a}}# #{{{{$a}}}}#';
			my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
				->output;
			assertEQ($rez,
				"#$expected# #$expectedUE#" ,
				"HTML Escape $string");
			}
			
=test special slots
		my %datapool = 
			(
			array => [qw(first second third)],
			);
		my $input = 'n={{$array.count}}';
		my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"n=3",
			"array count");
	
=test iterator nesting
	Test iteration cases
		my %datapool;
		my $input = "stuff\nmore stuff\n"
			.'{{ITERATE $array $itor}} no closing iterate'
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
				},
			qr/TagNotClosedError \{\{ITERATOR .* at line 3/,
			"Not closed iterator");
		
		$input = "stuff\nmore stuff\n"
			.'{{ITERATE $array $itor}}'."\n"
			.'{{ITERATE $b $c}} {{/ITERATE}}'."\n"
			."no closing iterate\n"
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new
					(text=>$input, datapool=>\%datapool)->output;
				},
			qr/TagNotClosedError \{\{ITERATOR .* at line 3/,
			"Not closed iterator with nested iterator");
		
		%datapool= ( b=>[1,2,3]);
		$input = "stuff\nmore stuff\n"
			.'{{ITERATE $b $c}} {{/ITERATE}}'."\n"
			.'{{ITERATE $array $itor}}'."\n"
			."no closing iterate"
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
					->output;
				},
			qr/TagNotClosedError \{\{ITERATOR .* at line 4/,
			"Not closed iterator after");
		
		$input = "stuff\nmore stuff\n"
			.'{{ITERATE $array $itor}} {{/ITERATE}}{{/ITERATE}}'
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
				},
			qr/ExtraCloseTagError \{\{\/ITERATOR .* at line 3/s,
			"Too many close iterators");
		
=test iterator
		my %datapool = 
			(
			array => [qw(first second third)],
			deeper => [ {key=>'first'}, {key=>'second'}, {key=>'third'} ],
			);
		my $input = '{{ITERATE $array $itor}} {{$itor_index}}#{{$itor}}# {{/ITERATE}}';
		my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" 0#first#  1#second#  2#third# ","Simple iterate");

		$input = '{{ITERATE $deeper $itor}} #{{$itor.key}}# {{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" #first#  #second#  #third# ","Deeper iterate");

		%datapool = 
			(
			array1 => [ 1,2,3 ],
			array2 => [ qw(a b c) ],
			aHash => {a => [1,2,3] },
			);
		$input = '{{ITERATE $array1 $outer}}{{ITERATE $array2 $inner}}{{$outer}}{{$inner}}{{/ITERATE}}{{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"1a1b1c2a2b2c3a3b3c","nested iterator");

		$input = '{{ITERATE $aHash.a $itor}} #{{$itor}}# {{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" #1#  #2#  #3# ","path to iterate");


=test if nesting
	Test the nesting of IF
		my %datapool;
		my @source = 
			(
			"stuff\nmore stuff\n"
			.'{{IF $a}} no closing'
			."\nend stuff\nmore end stuff",
			
			"stuff\nmore stuff\n"
			.'{{IF $a}}inbetween{{ELSE}} no closing'
			."\nend stuff\nmore end stuff",
			);
						
		foreach my $input (@source)
			{
			assertDie(
				sub
					{
					TemplateToPerl->new(text=>$input, datapool=>\%datapool)
				->output;
					},
				qr/TagNotClosedError \{\{IF .* at line 3/,
				"Not closed IF");
			}
			
		@source = 
			(
			"stuff\nmore stuff\n"
				.'{{IF $a}} {{/IF}}{{/IF}}'
				."\nend stuff\nmore end stuff",
			
			"stuff\nmore stuff\n"
				.'{{IF $a}} {{ELSE}}{{/IF}}{{/IF}}'
				."\nend stuff\nmore end stuff"
			);
		
		%datapool = (a=>1);				
		foreach my $input (@source)
			{
			assertDie(
				sub
					{
					TemplateToPerl->new(text=>$input, datapool=>\%datapool)
				->output;
					},
				qr/ExtraCloseTagError \{\{\/IF .* at line 3/s,
				"Too many close IF's");
			}
			
		my $input = "stuff\nmore stuff\n"
			.'{{IF $a}} no closing {{ITERATE $a $b}}{{/ITERATE}}'
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
				},
			qr/TagNotClosedError \{\{IF .* at line 3/s,
			"Not closed IF");

	orphaned else
		$input = "stuff\nmore stuff\n"
			.'{{IF $a}} n{{/IF}} afsdlkj {{ELSE}}'
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
				},
			qr/ExtraCloseTagError \{\{ELSE .* at line 3/s,
			"Not closed IF");
	
	extra else
		$input = "stuff\nmore stuff\n"
			.'{{IF $a}} n {{ELSE}}afsdlkj {{ELSE}}{{/IF}}'
			."\nend stuff\nmore end stuff";
		assertDie(
			sub
				{
				TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
				},
			qr/ExtraCloseTagError \{\{ELSE .* at line 3/s,
			"Not closed IF");

=test else nesting
	nested else
		my $input = 
			"{{IF \$a}}a1"
				."{{IF \$b}}b1{{ELSE}}b0{{/IF}}"
			."{{ELSE}}a0"
				."{{IF \$c}}c1{{ELSE}}c0{{/IF}}"
			."{{/IF}}"
			;
		my %dpsets = 
			(
			'a1b1' => [1,1,0],
			'a1b0' => [1,0,0],
			'a0c1' => [0,0,1],
			'a0c0' => [0,0,0],
			);
		
		my %datapool;
		while (my ($expected,$data) = each %dpsets)
			{
			@datapool{'a','b','c'} = @$data;
			
			my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
				->output;
			assertEQ($rez,
				$expected,"nested elses");
			
			
			}
			
=test If
		my %datapool = 
			(
			allTrue => [1,'a',[9,9],{a=>1}],
			allFalse => [0,'',undef],
			aHash => {t=>1, f=>0},
			);
		my ($ref1,$ref2) = ($datapool{'allTrue'}->[2], $datapool{'allTrue'}->[3]);
		my $input = '{{ITERATE $allTrue $itor}} #{{IF $itor}}{{$itor}}{{/IF}}# {{/ITERATE}}';
		my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" #1#  #a#  #$ref1#  #$ref2# ","Simple if");

		$input = '{{ITERATE $allTrue $itor}} #{{IF !$itor}}|{{$itor}}|{{/IF}}# {{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" ##  ##  ##  ## ","Simple !if");

		$input = '{{ITERATE $allFalse $itor}} #{{IF $itor}}|{{$itor}}|{{/IF}}# {{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" ##  ##  ## ","Simple if");

		$input = '{{ITERATE $allFalse $itor}} #{{IF !$itor}}|{{$itor}}|{{/IF}}# {{/ITERATE}}';
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			" #|0|#  #||#  #||# ","Simple !if");

		$input = '|{{IF $aHash.t}}t=t{{/IF}}'
			.'|{{IF $aHash.f}}f=t{{/IF}}'
			.'|{{IF !$aHash.t}}t=f{{/IF}}'
			.'|{{IF !$aHash.f}}f=f{{/IF}}'
			."|";
		$rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"|t=t|||f=f|","path to if");

=test interpolate cache
	Test that slots are only looked up once
		my $incr=45;
		my %datapool = 
			(
			incrementor => sub {$incr++},
			array => [1,2], # unused values
			counter => sub {$incr},
			a=>'b',
			);
		my $input = '#initial:{{$incrementor}}#2nd:{{$incrementor}}#'."\n"
		.'newline:{{$incrementor}}#{{IF $incrementor}}{{/IF}}#after if:{{$incrementor}}'
		.'#{{$array.{{$incrementor}}}}#after nested:{{$incrementor}}#{{$a}}{{$counter}}';
		my $rez = TemplateToPerl->new(text=>$input, datapool=>\%datapool)
			->output;
		assertEQ($rez,
			"#initial:45#2nd:45#\nnewline:45##after if:45##after nested:45#b46","Simple if");
			
=test ToDo
	Some To-do's

							
=end in-line-test
1;
