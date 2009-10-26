package HTTP::WebTestScript::Plugin::Verify;
use base qw(Exporter);
@EXPORT = qw(
	verify
	test
        log
	);

use Verbose; $kVerbose = 0;

use strict;
use warnings;
use Carp;
use HTTP::WebTestScript::Log;
use HTTP::WebTestScript::Plugin::Form();

=head1 verify comment, ...

You may substitute a regex anywhere below that there is text that you are looking for by supplying qr'...'. Note that qr"..." interpolates, as does qr/.../

If you use parenthesis in your qr//, the result from verify() will be undef or a ref to an array. Use this recipe
 
	my $rez = verify "match and extract", qr/number (\d+) named (.+)/;
	my ($valueIWant, $secondValueIWant) = @{ $rez || [] }; # perlism
	# now $valueIWant is either undef or the $1 match, etc.

=head2 verify text=>'text to match'

=head2 verify input=>'fieldName', value=>'text in that field';

=head2 verify select=>'selectName', value=>'valueThatShouldBeSelected'

=head2 verify element=>'tag name, i.e "body"', text=>'text/regex', 'someattribute'=>'text/regex'...

Find the element, test any/all of: it's text (till end-tag, collapse whitespace), it's attributes.

"not=>1" may be used.

=cut

=head1 test comment, ...

Just like verify, but doesn't croak, just returns true/false.

=cut

sub log {
    my ($desc) = @_;
    trace(1, log=>{description => $desc});
    return 1;
    }

sub test
	{
	my ($comment) = (scalar(@_) % 2) ? shift(@_) : undef;
	my (%args) = @_;
	my ($not) = (exists $args{'not'}) && $args{'not'}; delete $args{'not'};
	
	my @not = $not ? (not=>'not') : ();

        if (!$HTTP::WebTestScript::gResponse) {
		trace(0,verify=>{description=>$comment, failed=>"no current response",  %args , @not});
                return undef;
                }

	my $rez;
	
	(exists $args{'element'}) && do
		{
		my $element = delete $args{'element'};
		
		$rez = HTTP::WebTestScript::findTag($HTTP::WebTestScript::gResponse,$element, %args);
		$rez = !$rez if $not;
		# check for case-insensitive match & give information
		trace($rez,verify=>{description=>$comment,element=>$element, %args , @not});

		return $rez;		
		};
	
	(exists $args{'text'}) && do
		{
		my $text = delete $args{'text'};
		
		$rez = _verify_text($text);
		$rez = !$rez if $not;
		# check for case-insensitive match & give information
		trace($rez ? 1 : 0,verify=>{description=>$comment,text=>$text , @not});			

		return $rez;		
		};
	
	(exists $args{'input'} || exists $args{'field'}) && do # 'fields' is legacy
		{
		my $traceInfo;
		($rez,$traceInfo) = HTTP::WebTestScript::Plugin::Form::_verify_field(\%args); # will modify args
		$rez = !$rez if $not;
		trace($rez,verify=>{description=>$comment,%$traceInfo, @not});

		return $rez;		
		};
		
	(exists $args{'set'} || exists $args{'unset'}) && do
		{
		my ($command,$name) = exists($args{'set'}) ? (set=>$args{'set'}) : exists $args{'unset'} ? (unset=>$args{'unset'}) : undef;
		
		delete $args{$command};
		my $traceInfo;
		($rez,$traceInfo) = HTTP::WebTestScript::Plugin::Form::_verify_toggle($command=>$name,\%args);
		$rez = !$rez if $not;
		trace($rez,verify=>{description=>$comment,%$traceInfo, @not});

		return $rez;		
		};
	
	(exists $args{'select'}) && do
		{
		my ($name,$value) = delete @args{'select','value'};
		my $reason;
		($rez,$reason) = HTTP::WebTestScript::Plugin::Form::_verify_select($name,$value);
		my @fail = $rez ? () : (fail=>$reason);
		$rez = !$rez if $not;
		
		trace($rez,verify=>{description=>$comment,select=>$name,value=>$value, @fail, @not});

		return $rez;		
		};
			
	croak "Unknown arguments for TEST ",join(",",%args) if scalar (keys %args);
	return $rez;
	}
	
sub verify
	{
	my $rez = eval{ test(@_) };
	croak $@ if $@;
	return $rez || croak "Test failed '".join(" ",@_)."'";
	}
	
sub _verify_text
	{
	my ($text) = @_;
	
	# works for qr// too!
	#vverbose 4,"text ",ref($text)," $text\n";
	
	$text = quotemeta($text) if ref ($text) ne 'Regexp';
        confess "No response!" if !defined $HTTP::WebTestScript::gResponse;
	my @rez = $HTTP::WebTestScript::gResponse->content =~ /$text/;
	return scalar(@rez) ? \@rez : undef;
	}
	
1;

