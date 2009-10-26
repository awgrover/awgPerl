package lib::Template;
# copyright 2002 The Grove Group (Ann Arbor)

use strict;
use Verbose;
$kVerbose=0;

use Carp;

=pod

=h1 Usage
	
	my $cgi=CGI->new();
	
	my %datapool;
	
	# setup some slots in the datapool. These values can be used
	# by the template
	
	$datapool{'someslotname'} = $someValue;
	my $newHTML = lib::Template::doTemplate($cgi, \%datapool, $templateName);

TemplateName is relative to here:

	../templates/$templateName
	
=h1 Slots

A slot is just a perl expression starting with a key in the datapool.

Examples:
	{{$password}}	# interpolated as $datapool->{'password'}
	{{$session->username}}	# interpolated as $datapool->{'session'}->username
	{{$aHash->{'bob'}}}	# won't work, the } confuses things. sorry.
	{{$anArray->[4]}} # should work
	
Slots start with "$", followed by a key in the datapool hash, 
followed by proper perl syntax for complex structures.

"}" is forbidden in the slotname.

It is up to you to put the right data/structures in the datapool.

A simple slot (just a key) will work whether it "exists" in the hash or not, complex
slots (with "->", etc) will cause an error just like they would in regular perl code.

=cut

sub doTemplate
	{
	# Given the CGI, datapool and some HTML,
	# do the substitutions and return the fixed up HTML
	# do a perldoc on this file for usage in html
	my ($cgi, $datapool, $templateName ) =@_;
	die "sanity: no templateName" if !$templateName;
	
	my $fullTemplateName = "../templates/$templateName";
	
	die "sanity: '$fullTemplateName' doesn't exist" if !-f $fullTemplateName;

	my $html = `cat $fullTemplateName`;
	
	# FIXME: recursive. but careful of order
	$html = substIF($cgi, $datapool, $html);
	$html = substITERATE($cgi, $datapool, $html);
	$html = substSlotURLEscaped($cgi, $datapool, $html);
	$html = substSlot($cgi, $datapool, $html);
	
	print $html;
	}

=h1 HTML: {{$slot}}

In the HTML, replace with the value of the slot. Replaces everywhere. HTML escaped too!

=h1 HTML: {{{$slot}}}

Same, but url escaped.

=cut

sub substSlot
	{
	my ($cgi, $datapool, $html) = @_;
	
	$html =~ s/{{\$([^}]+)}}/_substSlot($cgi, $datapool,$1)/esg;
	return $html;
	}

sub _substSlot
	{
	my $cgi = shift;
	return $cgi->escapeHTML(evalSlot(@_));
	}

sub substSlotURLEscaped
	{
	my ($cgi, $datapool, $html) = @_;
	
	$html =~ s/{{{\$([^}]+)}}}/_substSlotURLEscaped($cgi, $datapool,$1)/esg;
	return $html;
	}

sub _substSlotURLEscaped
	{
	my $cgi = shift;
	return $cgi->escape(evalSlot(@_));
	}
	
	
sub evalSlot
	{
	# common code to get the value of a slot
	# expects the slotname, without a leading $
	my ($datapool, $slot) = @_;
	my ($firstSlot, $rest) = $slot =~ /^(\w+)(.*)?/;
	$rest ="" if !defined $rest;

	my $slotExpr = "\$datapool->{'$firstSlot'}$rest";
	
	my $expr = eval $slotExpr; confess "'$slot' ($slotExpr) failed: $@" if $@;
	$expr = "" if !defined $expr;
	
	#verbose "\$datapool->{'$firstSlot'}$rest =='",($expr),"'\n";
	vverbose 4, "\$$slot =='",($expr),"'\n";

	return $expr;
	}

=h1 HTML {{IF $slot ...html... ENDIF}}

If the $slot returns true, replace with the "...html...", otherwise, replace with ''.

Does not nest. Sorry.

=cut
		
sub substIF
	{
	my ($cgi, $datapool, $html) = @_;
	
	$html =~ s/{{IF \$([^\s]+)(.*)ENDIF}}/_substIF($datapool,$1,$2)/esg;
	return $html;
	}

sub _substIF	
	{
	my ($datapool, $slot, $content) = @_;
	
	my $boolean = evalSlot($datapool,$slot);
	
	return $boolean ? $content : "";
	}

=h1 HTML: {{ITERATE $slot iteratorName ... ENDITERATE}}

Repeats the content, once for each element in $slot (assumes an arrayref), sets $iteratorName
for each repeat: i.e. iterates.

Ex:
	{{ITERATE $results itor
	$itor->name<br>
	ENDITERATE}}

=cut

sub substITERATE
	{
	my ($cgi, $datapool, $html) = @_;
	
	$html =~ s/{{ITERATE \$([^\s]+) (\w+)(.*)ENDITERATE}}/_substITERATE($cgi, $datapool,$1,$2,$3)/esg;
	
	return $html;
	}

sub _substITERATE
	{
	my ($cgi, $datapool, $slot, $iterName, $content) = @_;
	verbose "iterate, saw $slot, $iterName\n";

	my $arrayRef = evalSlot($datapool,$slot);
	
	my @result;

	foreach (@$arrayRef)
		{
		my $aRow = $content; # copy

		$datapool->{$iterName} = $_;
		$aRow = substSlotURLEscaped($cgi, $datapool, $aRow);
		$aRow = substSlot($cgi, $datapool, $aRow);
		push @result, $aRow;
		}

	return join("",@result);
	}

sub fixme
	{
	verbose "FIX","ME: ",@_,"\n";
	}		

1;
