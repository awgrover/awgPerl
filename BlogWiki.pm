#!/usr/bin/env perl
package BlogWiki;
use Moose;
use strict;

# Runnable:
#       ./BlogWiki x... # produces x.html, y.html...
#       ./BlogWiki < # outputs html
#       perl BlogWiki.pm ... # as above
# Programmatically:
# $htmlizer = BlogWiki->new("a string" | $fileHandle);
#       nb: reads the file into memory.
# $html = $htmlizer->html

use Tie::InsertOrderHash;
use CGI qw(escapeHTML); # just for escapeHTML
use Verbose;
$kVerbose = $ENV{'VERBOSE'} || 0;


has _html => ( # cache for html()
    is => 'rw',
    );

has _textInput => (
    isa => 'Str',
    required => 1, # someday, other inputs
    is => 'rw',
    );

has footnotePrefix => (
    is => 'ro',
    default => uniqueToken()
    );

has _footnoteRenumber => (
    is => 'rw',
    default => 0
    );

has _footnoteRenumbering => (
    is => 'ro',
    default => sub{ {} }
    );

has _footerNotes => ( # saved up parsed footer-notes so far
    is => 'rw',
    default => sub { {} }
    );

has _footerNotesRaw => ( # saved up raw footer-notes so far
    is => 'rw',
    default => sub { {} }
    );

no Moose;

# Locals for the rules and parsing
our $patternCaller = '';
our $self;
our $onRuleNameChange  = undef;

our %Rules;
%Rules = (
    # named sets
    # subs as actions will have a local $self
    # You must escapeHTML/urlEscape your strings

    # pre is special, done first just with 'g'
    pre => [ # done with 'g' flag, iteratively
        # \n \s cleanup
        [qr/^[\s\n]*\n/s => ''],
        [qr/[\n\s]+$/ => ''], # trailing \n and \s
        [qr/^\s+$/m => "\n"], # blank lines gone
        ],

    # "regular" rules are anchored at ^
    # we move along 1 char at a time if nothing matches

    paragraph => orderedHash(
        # list of [ qr/.../ => string | sub

        # footer-notes start with [n]....
        # and go until $, next-footnote, or \n\n
        footerNote => [
            # We need to accumulate the footer-notes, so we can sort them.
            # We delay output till "rule match name at our level changes"
            # that lookahead is a bit tricky: if \n\[\d+\], consume the \n
            [qr/\[(\d+)\]\s*(.+?)(\n\n+|(?:(?=\n\[\d+\])\n)|$)/s => sub{
                vverbose 6,"footer '$1' '$2' '$3'";
                my $eol = $3;
                my $n = $1;
                my $footerBody = $2;
                my $newN;

                # renumber
                if (exists $self->_footnoteRenumbering->{$n}) { 
                    $newN = $self->_footnoteRenumbering->{$n};
                    warn "Warning: footer note $newN (mapped from $n) existed twice" if exists $self->_footerNotes->{$newN};
                    }
                else {
                    # didn't have a footnote, so put at bottom
                    warn "Warning: footer note $n didn't have a footnote\n";
                    my @sortedN = sort {$a <=> $b} values %{  $self->_footnoteRenumbering };
                    $newN = 1 + ((scalar @sortedN) ? $sortedN[-1] : 0);
                    $self->_footnoteRenumbering->{$n} = $newN;
                    }

                vverbose 6,"renumbered footer-note $n as $newN";
                # save it
                $self->_footerNotesRaw->{$newN} = $footerBody;
                $self->_footerNotes->{$newN} = [
                    "<a href='#foot-note-".$self->footnotePrefix."$newN' name='footer-note-".$self->footnotePrefix."$newN'>"
                    ."[".escapeHTML($newN)."]</a> ",
                    recurseParse($Rules{'chunk'}, $footerBody),
                    ($eol ? "<br />\n" : ())
                    ];
                # register our outputter
                onRuleNameChange( 
                    # tricky. we make this sub each time, but keep overwriting onRuleNameChange
                    # On flush, it is invoked, so all the data is there
                    sub{
                        my $fn = $self->_footerNotes;
                        $self->_footerNotes( {}) ; 
                        # We need to fixup the eols
                        # If any footer-notes are missing the eol, our reformed block needs to omit the final one too
                        # If they all have an eol, our block needs it too
                        # (and we have to fixup the one w/o the eol, since it is re-positioned)
                        my $eol = 1;
                        my @results = 
                            # flatten
                            map { 
                                my @aFooter = @{ $fn->{$_} };  # we know each one is a arrayref
                                if (!ref($aFooter[-1]) && $aFooter[-1] =~ /<br/) {
                                    }
                                else {
                                    # temporary "repair"
                                    push @aFooter, "<br />\n";
                                    $eol = 0;
                                    }
                                @aFooter; 
                                }
                                sort {$a <=> $b} keys %$fn;
                        if (!$eol) {
                            # remove the final eol if we shouldn't have one
                            pop @results;
                            }
                        vverbose 7,"total reform (eol=$eol) ",join(",", @results);

                        # warn if we don't have matching foot/footers (only for new-n's)
                        my %footNotesCheck;
                            @footNotesCheck{ values %{  $self->_footnoteRenumbering } } = (undef,);
                        my %reverseFootNoteLookup;
                            @reverseFootNoteLookup{ values %{  $self->_footnoteRenumbering } } = keys %{  $self->_footnoteRenumbering };
                        my @footerNotesCheck = keys %{ $fn };
                        delete @footNotesCheck{ @footerNotesCheck };
                        warn "Warning: footnotes w/o footer-notes: ",
                            join(", ",map {$reverseFootNoteLookup{$_}} keys %footNotesCheck)."\n"
                            if scalar(keys %footNotesCheck);

                        return \@results;
                        }
                    );
                return undef;
                }],
            ],

        # <p> paragraphs end with \n\n or $
        p => [
            # p's are ended by \n\n+
            [qr/(.+?)\n\n+/s => sub{ # non-greedy to prevent backtracking, but allow internal \n
                vverbose 6,"paragraphing-eop '$`'";
                return ['<p>',recurseParse($Rules{'chunk'}, $1),"</p>\n\n"];
                }], # collapses \n runs too
            # p's are ended by end-of-string
            [qr/(.+)$/s => sub{ 
                vverbose 6,"paragraphing-eos '$1'";
                return ['<p>',recurseParse($Rules{'chunk'}, $1),'</p>'];
                }], # collapses \n runs too
            ],
        ),

    chunk => orderedHash(
        # Each is: name => [patterns=>actions ...]
        # The patterns are tried in the order given (as if a flat space).
        # But, if you call parseRecurse, it will skip the current "name"
        
        footnote => [
            # list of [ qr/.../ => string | sub ]
            [qr/\s*\[(\d+)\]/ => sub {
                my $n = $self->footnoteRenumber($1);
                vverbose 6,"footnote $1";
                return [
                    "<a href='#footer-note-".$self->footnotePrefix."$n' name='foot-note-".$self->footnotePrefix."$n'",
                    # Tricky, delayed production to get body of footnote
                    sub {
                        if (exists($self->_footerNotesRaw->{$n})) {
                            my $footerNote = $self->_footerNotesRaw->{$n};
                            $footerNote =~ s/\n/ /g;
                            return " title='".escapeHTML($footerNote)."'";
                            }
                        return "";
                        },
                    ">"
                    ."<sup>",
                    escapeHTML($n),
                    "</sup></a>"
                    ];
                }],
            ],

        http => [
            # tricky, fail if ". Cap"
            [qr/(http:[^ ]+?), ((?:.(?!\. [A-Z]))+?),/ => sub{
                "<a href='$1'>".escapeHTML($2)."</a>";
                }],
            [qr/http:.+?(?=[[:punct:]]?(?:\s|$))\/?/ => sub{
                "<a href='$&'>".escapeHTML($&)."</a>";
                }],
            ],
        ),

    # post is special, done with 'g'
    post => [ # unordered , done with 'g' flag
        # qr/$/ => '</p>', 
        ],
    );

sub BUILDARGS {
    # Allow single arg for various input types
    my $class = shift;
    
    if (@_ == 1) {
        if (! ref $_[0]) {
            return { _textInput => $_[0] }
            }
        else {
            if (ref($_[0]) eq 'GLOB' && *{$_[0]}{IO}) {
                my $fh = $_[0];
                my $text = join("", <$fh>);
                return { _textInput =>  $text }
                }
            elsif ($_[0]->isa('IO::Handle')) {
                my $fh = $_[0];
                my $text = join("", <$fh>);
                return { _textInput =>  $text }
                }
            }
        }

    return $class->SUPER::BUILDARGS(@_);
    }

sub html {
    # return the html interpretation
    # cached
    local $self = shift;
    # @_ is the name of rules: a->b->c...
    return $self->_html if defined $self->_html;

    my $text = $self->_textInput;

    # pre-cleanup
    globalActions($Rules{'pre'}, $text);
    vverbose 6,"after pre: '$text'";

    # use @_ as a path to th rule in %Rules, default = 'paragraph'
    my $rules = \%Rules;
    if (scalar @_) {
        foreach (@_) {
            $rules = $rules->{$_};
            }
        }
    else {
        $rules = $Rules{'paragraph'};
        }
    my $res = recurseParse($rules, $text);
    my $html = join("", map{ (ref($_) eq 'CODE') ? &$_() : $_ } @$res);
    vverbose 6, "rules done";

    globalActions($Rules{'post'}, $html);
    
    return $self->_html($html);
    }
        
sub orderedHash {
    tie my %h => 'Tie::InsertOrderHash', @_;
    return \%h;
    }

sub recurseParse {
    # We produce pieces, each piece is either a string, or a sub that produces a string.
    # This allows the subs to resolve forward references.
    # So, each rule should produce an arrayref of pieces, or a sub, or a string
    # and we'll smartly append the result
    my ($rules, $nextPiece) = @_;
    die "no rules" if !defined $rules;

    # I was going to operate on $_[-1], so I wouldn't have to copy the string so
    # much, but something I'm doing causes $_[-1] to suddenly become ''. So,
    # now I copy.

    # local $patternCaller; # set below
    # call this on rule-name-change, but only in this "cycle" (not in recursed children)
    local $onRuleNameChange = undef; # set by actions via  onRuleNameChange

    my $iSofar = 0;
    my @res = (""); # initial empty string for single-char accum optimization below

    # reform rules
    # First, to flatten them.
    # Second, we don't want a recurse to try to apply the same rule again, 
    # e.g. qr/http:.../ => "<a...>".recurse($&)."</a>".
    # As a side effect, we get a new rule hash, and its iterator for recursion
    # New form is pattern => [name, action]
    my @myRules;
    if (ref($rules) eq 'HASH') {
        while (my ($name, $ruleSet) = each %$rules) {
            next if $name eq $patternCaller;
            die "During $name, trying to flatten its values, expected ARRAY, found ".ref($ruleSet) if ref($ruleSet) ne 'ARRAY';
            push @myRules, map{
                die "During $name, trying to flatten an element in its values, expected ARRAY, found ".ref($_) if ref($_) ne 'ARRAY';
                [$name, @$_]} @$ruleSet;
            }
        }
    else {
        my $i=0;
        @myRules = map {[$i++, @$_]} @$rules; # copy gives my an iterable
        }
    vverbose 6, "myrules ".Dumper(\@myRules)." "; use Data::Dumper;

    # local sub for handling rulename change
    my $doRuleNameChange = sub {
        if ($onRuleNameChange) {
            vverbose 6,"Fire rulechange changing"; 
            my $results = &$onRuleNameChange();
            vverbose 7,"    total result ",join(",", @$results);
            # flatten
            push @res, map{(ref($_) eq 'ARRAY') ? @$_ : $_} @$results;
            vverbose 6,"  rule-change result gave: ".$results," [-1]:".$res[-1];
            $onRuleNameChange = undef;
            }
        };

    vverbose 6,"<Recurse on ($patternCaller)".$nextPiece;

    my $lastPatternName = undef;

    do {
        vverbose 6,"try '".$nextPiece."'";
        my $hit = 0;

        # find first pattern that matches at ^
        foreach my $info (@myRules) {
            my ($name, $pattern, $action) = @$info;
            vverbose 6, "do $name: $pattern => $action";
            vverbose 6,"  against \n'".$nextPiece."'";

            if ($nextPiece =~ m/^$pattern/s ) {
                # preserve $1, $2, ... until we call the action!
                no warnings 'uninitialized'; vverbose 6,"   hit $name: \n'$`\n'>>>\n'$&'\n\$1='$1' \$2='$2' \$3='$3'";  use warnings;
                # flush if somebody is waiting for their "section" to end
                if ($lastPatternName && $name ne $lastPatternName) {
                    vverbose 6,"rule name change $lastPatternName => $name";
                    &$doRuleNameChange();
                    }
                $lastPatternName = $name;

                $nextPiece = $';
                push @res, escapeHTML($`);

                local $patternCaller = $name; # should inhibit named rules from firing again

                # we need the preserved $1, $2, ... for the action!
                my $ruleResult = (ref $action) ? &$action() : $action;

                # Accumulate: append a arrayref, assume "atomic" piece otherwise (sub or string)
                if (ref($ruleResult) eq 'ARRAY') {
                    # the result could be a list, and an element could be from calling recurseParse
                    # so, flatten
                    push @res, map{(ref($_) eq 'ARRAY') ? @$_ : $_} @$ruleResult;
                    }
                else {
                    push @res, $ruleResult if defined $ruleResult;
                    }
                no warnings 'uninitialized'; vverbose 6,"  action gave: ".$ruleResult," [-1]:".$res[-1]; use warnings;

                # indicate that we found a match, stop trying, move along to $'
                $hit = 1;
                last;
                }
            vverbose 6,"  no match, still at \n'".$nextPiece."'";
            }


        # if nothing matched, move 1 char ahead
        if (!$hit) {
            # terminal rulenamechange
            &$doRuleNameChange();
            $lastPatternName = undef;

            # instead of accumulating a bunch of single chars, append single chars
            if (! ref $res[-1]) {
                $res[-1] .= escapeHTML(substr($nextPiece,0,1));
                }
            else {
                push @res, escapeHTML(substr($nextPiece,0,1));
                }
            vverbose 6,"no hit, accum 1 char ".$res[-1];
            $nextPiece = substr($nextPiece,1);
            }

        vverbose 6,"".($hit ? "matched a rule" : "nothing matched")." at ^, next is "
            .($hit ? "\$'" : "next char")."\n '$nextPiece'";


        } while ($nextPiece);
    vverbose 6,">Recursed, result = ",join(",",@res);

    # terminal rulenamechange
    &$doRuleNameChange();

    return \@res;
    }

sub globalActions {
    my ($rules) = @_;

    vverbose 8,"## global on '".$_[-1]."'";
    foreach my $pa (@$rules) {
        my ($pattern, $action) = @$pa;
        vverbose 8,"global ".ref($pattern)." $pattern => $action";
        die "$pattern wasn't a regexp" if ref($pattern) ne 'Regexp';

        if (ref $action) {
            $_[-1] =~ s/$pattern/&$action()/ge;
            }
        else {
            $_[-1] =~ s/$pattern/$action/eg;
            }
        vverbose 8,"   rez '".$_[-1]."'";
        }
    }
    
sub xparse {
    # set the html interpretation
    # via lazy getter
    my $self=shift;

    my $text = $self->_textInput;

    # trim blank lines;
    $text =~ s/^\n+//;
    $text =~ s/\n+$//;

    # reduce \n runs
    $text =~ s/\n\n\n+/\n\n/g;

    # over exuberant <p></p>, but also incomplete
    $text =~ s/\n\n/<\/p><p>/g;

    # fix head
    $text = "<p>" . $text;

    # fix tail
    $text .= "</p>";

    # put convenience \n\n back
    $text =~ s/<\/p>/<\/p>\n\n/g;
    $text =~ s/\n+$//;

    return $text;
    }

sub footnoteRenumber {
    # build a hash of  $self->_footnoteRenumbering->{$textual_n} = $shouldbe_n
    # footernotes use it to renumber.
    my $self=shift;
    my ($n) = @_;
                
    # remember old=>new mapping
    if (defined $self->_footnoteRenumbering->{$n}) {
        return $self->_footnoteRenumbering->{$n};
        }
    else {
        my $newN = $self->_footnoteRenumber + 1;
        $self->_footnoteRenumbering->{$n} = $newN;
        $self->_footnoteRenumber($newN);
        return $newN;
        }
    }

sub onRuleNameChange {
    # this var is localized in recurseParse
    vverbose 6,"set onrulenamechange";
    $onRuleNameChange = $_[0];
    }
    
sub uniqueToken {
    # a unique-string for each article's footnotes
    return join("", map { chr(rand(26)+ord('A')) } (1..30));
    }

# Run if we were the invoked file
if ($0 eq __FILE__) {
    if (scalar @ARGV) {
        require IO::File;
        my $wrap;
        if ($ARGV[0] eq '-w') {
            shift @ARGV;
            $wrap = 1;
            }
        foreach my $infile (@ARGV) {
            my $outfile = $infile;
            # replace short extension with .html
            ($outfile =~ s/\..{3,4}$/.html/) || ($outfile .= ".html");
            my $inH = IO::File->new("<$infile") || die "Can't read from $infile, $!";
            my $outH = IO::File->new(">$outfile") || die "Can't write to $outfile, $!";
            print $outH "<html><head><title>$infile</title></head><body>\n" if $wrap;
            print $outH BlogWiki->new($inH)->html;
            print $outH "\n</body></html>" if $wrap;
            $inH->close; $outH->close;
            }
        }
    }
1;

