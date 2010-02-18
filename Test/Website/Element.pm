package Test::Website::Element;
use warnings; use strict; no warnings 'uninitialized';

use base qw(Exporter);
our @EXPORT    = qw(
    element
    not_element
    xpath
    follow
    );

use import qw(
    %Test::Website::PageCache
    $Test::Website::Response
    &Test::Website::_get
    $Test::Website::kVerbose
    );
use Verbose; $kVerbose = $ENV{'VERBOSE'} || 0;


use HTML::TreeBuilder::XPath;
use XML::TreeBuilder; # also monkey patched like HTML::TreeBuilder to include the ::XPath methods
use Test::Website::Log;
use Data::Dumper;
use Carp;
use Test::Builder::Module;


=head2 <element-predicate>...

These are the arguments to most of the tests (e.g. L</"element">), specifies the element in the html document.

You can have multiple predicates (see below).  The predicates are usually and'd together, but see "attr=>value" below.

There are some short-hands (e.g. L</form>), and see each command (e.g. L<element|element__elementpredicate____>) for special short-hand predicates.

NB: Some predicates take a list of predicates, e.g.
    in => { .... }
You may not repeat key-names in such a list, e.g. wrong: in => { id=>'x', id=>'y' }

=head3 attr => "value", ...

Basic "atribute has value" predicate. May have several
with the same attribute name. If you repeat a "attr", they will be or'd.

The attr and value can be:

        literals
        qr//
        sub(HTML::Element) {return t/f} # not implemented yet

Notes on regex's:

For your convenience, a predicate of { text => qr/..../ } will capture the match as an arrayref HTML::Element->attr('_re').
The first element of the arrayref is the entire regex match, and then your capturing parenthesis. E.g.

    $res = element text => qr/login (for admin)/;
    ($wholeMatchedRegex, $justForAdmin) = @{ $res->attr('_re') };

The HTML::Element->look_down() method is used to find elements that match the predicate. It appears to
to have this peculiar behavior:

    $ matches the end of the text (not end-of-line)
    . does not match end-of-lines

So, qr/.+$/ will typically fail. But, qr/blah blah.+/ will match to the end of line. You can specify
regex flags, 'm' and 's', to get the behavior you desire. E.g qr/blah+.$/m will match till end of line.

Also, given that you supply the regex via qr//, you can't specify the 'g' flag.

=head4 psuedo attr: tag

The tag-name, e.g. "html"

=head4 psuedo attr: n

The position, given the rest of the predicates.  Toplevel predicate only. Short-hand for something like:

    @res = element .....
    $n < scalar(@res) ? $res[$n] : undef;

=head3 xpath("expr"), OR xpath=>"expr"

Restrict to the nodes that satisfy the expr. Predicates then apply to that list.

Not compatible with "in". Only usable at the "top-level" of a predicate list, e.g.,
not within "not", etc.

=head3 not => {element-predicate...}

Means "and not <element-predicates>".

Read something like "for the element: and not 1, and not 2, and not 3."

NB:

    element not => { stuff }    # wrong

will never fail. You probably want:

    not_element stuff...

=head3 first-of => {element-predicates}

Acts like:

    other-predicates and firstof1
    or other-predicates and firstof2
    ...

E.g. The first alternative.

If you want this behavior: 

    other-predicates and (a or b or c), 

do a qr// or sub{}

    ..., qr/^a|b|c$/ => somevalue

=head3 in => {element-predicate}

    "in an element with <element-predicates>."

    Not compatible with using xpath.

=head3 Short-hand form => "id or action or name or n" 

For 

    in => {tag => "form", first-of => {id=>"x", action=>"x", name=>"x", n => "x"}}

=cut

sub buildPredicate {
    tie my %args, 'Test::Website::Element::PredicateList' => @_;

    vverbose 2,"build: ",join("=>",map {"$_(".ref($_).")=>".$args{$_}} keys %args);
    my @and;

    # not
    if (my $not = delete $args{'not'}) {
        
        vverbose 4,"build not: ",join("=>",(ref($not) eq 'HASH' ? %$not : @$not));
        my $notP = buildPredicate(ref($not) eq 'HASH' ? %$not : @$not);
        push @and, sub { 
            vverbose 4, "not(";
            my $res = ! &$notP(@_);
            vverbose 4, " )=".($res ? 1 : 0)." ";
            return $res;
            };
        }

    # attr's
    if (%args) {
        push @and, sub {
            my ($node) = @_;
            my $found = 1;
            vverbose 4, ("Test for ".$node->starttag."\n");

            keys %args;

            # "and" each attribute test value
            while (my ($testAttr,$testValues) = each %args) {
                $testValues = (ref($testValues) eq 'ARRAY') ? $testValues : [ $testValues ];

                vverbose 4, ("values ".join(",",@{(ref $testValues) ? $testValues : [$testValues]})." for ".ref($testAttr)." $testAttr");
                confess ".... found hash for attribute '$testAttr'" if ref $testValues eq 'HASH';

                # since the test-attribue-name could be a regex,
                # we have to filter for candidate attributes
                vverbose 4,"setup for $testAttr = ".join(",",@$testValues)." in attributes ".join(", ",$node->all_attr_names());
                my @candidateValues = 
                    map {
                        vverbose 4, "    candidate value for $_ ==? $testAttr";
                        if ($_ eq 'text') {
                            $node->content_list;
                            }
                        else {
                            $node->attr( $_)
                            }
                        }
                    grep {
                        my ($r) = (ref($testAttr) eq 'Regexp')
                            ? $_ =~ $testAttr
                            : $_ eq ($testAttr eq 'tag' ? '_tag' : $testAttr)
                            ;
                        vverbose 6,"## filter: is extant attr '$_' match for ".ref($testAttr)." $testAttr? -> '$r'";
                        $r;
                        } ($node->all_attr_names(),'text');
                
                vverbose 4,"  candidate attr ct ".@candidateValues," : ",join(", ",@candidateValues);

                # for this attr, one of the candidate-values has to match one of the test-values

                my $one_of = 0;

                ATTR_MULTI:
                foreach my $attrV (@candidateValues) {
                    foreach my $testValue (@$testValues) {
                        vverbose 4,"   test $testValue vs $attrV";
                        if (ref($testValue) eq 'Regexp'
                                ? $attrV =~ $testValue
                                : $attrV eq $testValue) {
                            $one_of = 1;
                            last ATTR_MULTI; # short-circuit "or"
                            }
                        }
                    }
                $found &= $one_of;

                # if none of the values matches, fail
                vverbose 4,"  ".$node->starttag." =$found";
                last if !$found; # short-circuit "and"
                next;
                }

            vverbose 4,"Match by attr? ".$node->starttag." $found";
            return $found;
            };
        }

    my $pred;
    if (@and > 1) {
        $pred = sub { 
            my $found = 1; 
            vverbose 4, ("and(");
            foreach (@and) { 
                $found &= &$_(@_); 
                vverbose 4, (", ");
                }
            vverbose 4, (")=".($found?1:0)." ");
            return $found
            };
        }
    else {
        $pred = $and[0];
        }

    return $pred;
    }

=head2 element <element-predicate>...

    If the element exists in the document
        return the first one, and log success
        the returned thing is a HTML::Element
    else 
        log failure 
        die

In an array contex, You will get all the matching elements (of type L<HTML::Element>).

See L<maybe|/maybe_____elementpredicate____>, below, for inhibiting the "die."

=head3 Short-hand: element "tagname" 

For 

    element tag=>"tagname".

=head3 Predicate maybe => {element-predicate...}

As if the predicates, but means "don't fail, return null". Changes "element" from 
an assertion to "find element or null." Generally, put all the predicates are in the "maybe."

=head3 Idiom: find an element

element maybe=>{predicates...}

Inhibits the "die" if the element is not found.

Returns the first match (or undef) in scalar context, all matches in array context.

=head3 Short-hand not_element ... 

For "no such element", something like (cf. L<not|/not_____elementpredicate____>)

    not element maybe => {...} || fail...

=head3 Short-hand maybe-element ... 

For 

    element maybe => {...}

=head3 Short-hand all-element ... for element all => {...}

=head3 Short-hand field "name" ... 

For 

    element tag => qr/select|checkbox|.../, ..., first-of => {id=>"x", action=>"x", name=>"x"}

=cut

sub not_element {
    element(@_, _not => 1);
    }

sub element {
    # hidden arg "_not";

    if (scalar(@_) % 2) {
        if (ref($_[0]) eq 'XPATH') {
            $_[0] = "".$_[0]; # stringify
            unshift @_,"xpath";
            }
        else {
            unshift @_,"tag";
            }
        }
    tie my %args, 'Test::Website::Element::PredicateList' => @_;
    tie my %originalArgs, 'Test::Website::Element::PredicateList' => @_; # we operate on %args
    # vverbose 0,"ELEMENT orig ".Dumper(\@_);
    # vverbose 0,"ELEMENT ".Dumper(\%originalArgs);

    # expand short-hands

    my $maybe;
    if ($maybe = delete $args{'maybe'}) {
        # promote the preds. 'maybe' is just a flag
        vverbose 2,"rebuild from maybe";
        @args{keys %$maybe} = values %$maybe;
        }

    # "not any" as opposed to "any w/not..."
    my $_not = delete $args{'_not'} ? 1 : 0; # canonical the value

    my @res = _element(%args);

    # tricky, success is opposite of _not arg
    my $ok = 
        @res
        ? !$_not
        : $_not 
        ;

    trace($ok, ($_not ? 'not_' : "").'element' => \%originalArgs, because => "not found", maybe => $maybe);

    return wantarray ? @res : (scalar(@res) ? $res[0] : undef);
    }

sub _parse {
    return $PageCache{'parsed'} if $PageCache{'parsed'};

    my $tree;

    my $type = $Test::Website::Response->header('content-type');

    if ($type =~ /(\+xml(;|$))|(^(application|text)\/xml(;|$))/ && $type !~ /\/xhtml+xml(;|$)/) {
        vverbose 2,"parsed as XML";
        $tree = XML::TreeBuilder->new();
        $tree->parse($Test::Website::Response->content);
        }
    else {
        vverbose 2,"parsed as HTML";
        $tree = HTML::TreeBuilder::XPath->new_from_content($Test::Website::Response->content);
        }
    $tree->elementify if !$tree->isa('HTML::Element');;
    $PageCache{'parsed'} = $tree;

    return $tree;
    }

sub _element {
    tie my %args, 'Test::Website::Element::PredicateList' => @_;
    
    return undef if !$Test::Website::Response;

    my $ith = delete $args{'n'};
    $ith -= 1 if defined $ith; # nth vs ith

    # list of trees, for xpath later
    my @trees = _parse();

    # get xpath results first
    my $xpath;
    if ($xpath = delete $args{'xpath'}) {
        @trees = $trees[0]->findnodes($xpath);
        vverbose 2,"xpath: ".$xpath. " = ".scalar(@trees);
        }

    vverbose 1,"Build from args: ",join("=>", map {"<".ref($_).">$_"} %args),"\n\t";
    my $xpred = buildPredicate(%args);
    my $pred = $xpred;

    my @elements;

    if (!$pred) {
        @elements = @trees if $xpath;
        }
    else {
        vverbose 3,("search: ",join("=>", %args),"\n\t");
        my $i=1;
        foreach (@trees) {
            vverbose 3,("tree ".($i++));
            push @elements, $_->look_down($pred);
            }
        }

    vverbose 1,"found ".@elements; # ." ".Dumper($elements[0])."...";

    if (defined $ith) {
        @elements = $elements[$ith];
        }
   
    # gather the regex matches for the text thing
    if (defined $args{'text'} && ref($args{'text'}) eq 'Regexp') {
        my $regex = $args{'text'};
        # vverbose 0,"TExT regex $regex";
        foreach my $element (@elements) {
            foreach ($element->content_list) {
                if (!ref $_) {
                    if (my @res = ($_ =~ /($regex)/)) {
                        # vverbose 0,"HIT in $_ \t::".join("\n\t::",@res)."\n";
                        $element->attr('_re', \@res);
                        }
                    }
                }
            }
        }
    return  wantarray ? @elements : (scalar(@elements) ? $elements[0] : undef);
    }

=head2 follow element <element-predicates>

Really, the same as

    my $e = element ....;
    follow $e;

=head3 Short-hand follow <element-predicates> 

For

    follow element <element-predicates>

=head3 Short-hand follow 'hrefvalue'; or follow qr/hrefvalue/, ... 

A single argument is assumed to be for the href attribute (unless the arg is the result from an "element", see L<above|follow_element__elementpredicates_>).

    follow tag=>'a', href=>hrefvalue, ...


=cut

sub follow {
    my $link;
    if (scalar(@_) == 1 && ref $_[0] eq 'HTML::Element') {
        $link =  $_[0];
        @_ = ( 'obj' => $link->starttag );
        }
    elsif (scalar(@_) % 2) {
        unshift @_, 'href';
        push @_, ( tag => 'a' );
        }

    $link = $link || _element(@_);

    if (!$link) {
        trace(0, follow => [@_], because => "link not found");
        }

    if ($link->tag ne 'a') {
        trace(0, follow => [@_], because => "that's not a link: ".$link->starttag);
        }

    my $url = $link->attr('href');

    my $res = _get(command=>'follow',url=>$url, method=>'GET', base => $Response->base);
    verbose "got ".$res->status_line;
    trace($res->is_success, follow => [@_], because => "Status was ".$res->status_line);

    return $res;
    }

END {
    }

sub xpath {
    # just package the string as an XPATH.
    bless \$_[0], "XPATH";
    }

package XPATH;
use overload
    '""' => sub {${$_[0]}};

package Test::Website::Element::PredicateList;
# hash implementation
# allows refs as keys
# assigning to an existing key, makes the value an array and pushes the new value
use Verbose;

sub TIEHASH  {
    my ($class) = shift;
    my $self = bless {alist => [], iter => 0}, __PACKAGE__;

    foreach my $i (0 .. scalar(@_) / 2 -1 ) {
        my $k = $_[$i * 2];
        my $v = $_[$i * 2 + 1];
        # vverbose 0,"$i: ".ref($k)." $k => $v";
        STORE($self, $k, $v);
        }
    # vverbose 0,"is ".Dumper($self)." from ".join(", ",@_); use Data::Dumper;
    return $self;
    }

sub STORE {
    my ($self, $k, $v) = @_;
    my $extant = entry($self, $k);

    if (defined($extant)) {
        if (ref $extant->[1] eq 'ARRAY') {
            # vverbose 0,"add to $k, $v";
            push @{ $extant->[1]}, $v; # add v
            }
        else {
            # vverbose 0,"convert, and add to $k, $v";
            $extant->[1] = [$extant->[1], $v]; # convert v to list of v
            }
        }
    else {
        # vverbose 0,"set $k => $v";
        push @{$self->{'alist'}}, [ $k, $v ]; # a-list pair
        }
    }

sub entry {
    my ($self, $k) = @_;
    my $res;
    foreach (@{$self->{'alist'}}) {
        # vverbose 0,"entry for $k? ".Dumper($_);
        if ($k eq $_->[0]) {
            return $_;
            }
        }
    # vverbose 0,"no such $k";
    return undef;
    }

sub EXISTS {
    my ($self,$k) = @_;
    entry($self, $k);
    }

sub FIRSTKEY {
    my $self = shift;
    $self->{'iter'} = 0;
    # vverbose 0,"first key ". $self->{'alist'}->[0]->[0];
    return scalar(@{$self->{'alist'}}) 
        ? $self->{'alist'}->[0]->[0] 
        : ();
    }

sub FETCH {
    my ($self, $k) = @_;
    if (my $entry = entry($self, $k)) {
        # vverbose 0,"fetch $k => ".Dumper($entry);
        return $entry->[1];
        }
    return undef;
    }

sub NEXTKEY {
    my $self=shift;
    my $i = ++$self->{'iter'};
    my $data = $self->{'alist'};
    # vverbose 0,"next key $i";
    return $i < scalar(@$data) 
        ? $data->[$i]->[0]
        : ()
        ;
    }

sub DELETE {
    my ($self, $k) = @_;
    return undef if ! scalar(@{$self->{'alist'}});

    my $data = $self->{'alist'};
    foreach (0 .. scalar(@$data) - 1) {
        if ($k eq $data->[$_]->[0]) {
            my $res = $data->[$_]->[1];
            splice(@$data, $_,1, ());
            return $res;
            }
        }
    return undef;
    }

sub SCALAR {
     scalar(@{shift->{'alist'}});
     }

sub DESTROY {
    my $self = shift;
    $self->{'alist'} = undef;
    }

sub CLEAR {
    shift->{'alist'} = [];
    }

package Test::Website::Element;
1;
