#!/usr/bin/env perl
package awg::BlogWiki_test;

use Test::Behaviour::Spec;
use Test::More 'no_plan';
use Test::Differences;
use CGI qw(escapeHTML);

use Tie::InsertOrderHash;
use Verbose;

describe "module sanity";
    it "should load";
        BEGIN {use_ok BlogWiki}

describe "paragraph inference";

    tie my %paragraphTests => 'Tie::InsertOrderHash', (
            # basic 1 p
            "p1" => "<p>p1</p>",
            # 2 p's
            "p1\n\np2" => "<p>p1</p>\n\n<p>p2</p>",
            # leading/trailing \n and \s
            "\np1\n" => "<p>p1</p>",
            "\n\np1\n\np2" => "<p>p1</p>\n\n<p>p2</p>",
            " \np1\n " => "<p>p1</p>",
            " \np1 \n" => "<p>p1</p>",
            " \np1\n \np2" => "<p>p1</p>\n\n<p>p2</p>",
            "p1\n\np2\n\n\n" => "<p>p1</p>\n\n<p>p2</p>",
            # embedded \n in p's
            "p1\n\np2\nnot-p3" => "<p>p1</p>\n\n<p>p2\nnot-p3</p>",
            "\np1\n\np2\nnot-p3\n" => "<p>p1</p>\n\n<p>p2\nnot-p3</p>",
            "\np1\n\np2\nnot-p3\n\n" => "<p>p1</p>\n\n<p>p2\nnot-p3</p>",
            "p1\n\np2\nnot-p3\n\n\n" => "<p>p1</p>\n\n<p>p2\nnot-p3</p>",
            "a\nb\n\nC" => "<p>a\nb</p>\n\n<p>C</p>", # \n in first paragraph
            # multipe \n's collapse
            "p1\n\n\n\np2" => "<p>p1</p>\n\n<p>p2</p>",
            );
    while (my ($in, $out) = each(%paragraphTests)) {
        last if $in eq 'STOP';

        it "should do <p>'s for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            is $it->html, $out, spec;

        }

describe "make footnotes into sup-links";
    tie my %footnoteTests => 'Tie::InsertOrderHash', (
            "p1 has [1] footnote1" => "p1 has".mk_footnote(1)." footnote1",
            "p1 has [1] footnote1, and[2] note" => "p1 has".mk_footnote(1)." footnote1, and".mk_footnote(2)." note",
            "p1 has [1] footnote1\n\np2 has footnote[2]." => "p1 has".mk_footnote(1)." footnote1\n\np2 has footnote".mk_footnote(2).".",
        );

    while (my ($in, $out) = each(%footnoteTests)) {
        last if $in eq 'STOP';

        it "should do <a href='#...'><sup>... for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(qw(chunk footnote)), $out, spec;

        }

describe "distinguish footernotes from paragraphs";
    tie my %footerPTests => 'Tie::InsertOrderHash', (
            # don't care to test string beginning with footer-note
            # basic p1 + footernote
            "p1\n\n[1] foot1" => "<p>p1</p>\n\n".mk_footernote(1)." foot1",
            # trim \n (should be same as paragraph trim, since it is global)
            "p1\n\n[1] foot1\n" => "<p>p1</p>\n\n".mk_footernote(1)." foot1",
            # 2 foot notes
            "p1\n\n[1] foot1\n[2] foot2" => "<p>p1</p>\n\n".mk_footernote(1)." foot1<br />\n".mk_footernote(2)." foot2",
            "p1\n\n[1] foot1\n[2] foot2\n" => "<p>p1</p>\n\n".mk_footernote(1)." foot1<br />\n".mk_footernote(2)." foot2",
            # multi-paragraph just to check 1..2 p case
            "p1\n\np2\n\n[1] foot1\n[2] foot2\n" => "<p>p1</p>\n\n<p>p2</p>\n\n".mk_footernote(1)." foot1<br />\n".mk_footernote(2)." foot2",
        );

    while (my ($in, $out) = each(%footerPTests)) {
        last if $in eq 'STOP';

        it "should do <p>'s and footer-notes for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html, $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "footer-notes";
    tie my %footerTests => 'Tie::InsertOrderHash', (
            # footer-note with embedded \n
            "[1] fwbreak\not1" => "".mk_footernote(1)." fwbreak\not1",
            # footer-note with embedded \n followed by footer
            "[1] fwbreak\not1\n[2] fer2" => "".mk_footernote(1)." fwbreak\not1<br />\n".mk_footernote(2)." fer2",
            # footer-note followed by footer
            "[1] fer1\n[2] fer2" => "".mk_footernote(1)." fer1<br />\n".mk_footernote(2)." fer2",
            "[1] fer1\n\n[2] fer2" => "".mk_footernote(1)." fer1<br />\n".mk_footernote(2)." fer2",
        );

    while (my ($in, $out) = each(%footerTests)) {
        last if $in eq 'STOP';

        it "should do <p>'s and footer-notes for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(qw(paragraph footerNote)), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "foot-notes with tool-tips";
    tie my %footToolTipTests => 'Tie::InsertOrderHash', (
            # 1
            "a [1]\n\n[1] footer1" => "<p>a".mk_footnote(1,'footer1')."</p>\n\n".mk_footernote(1)." footer1",
            # 2
            "a [1] b[2]\n\n[1] footer1\n[2] footer2" => "<p>a".mk_footnote(1,"footer1")." b".mk_footnote(2,"footer2")."</p>\n\n"
                .mk_footernote(1)." footer1<br />\n".mk_footernote(2)." footer2",
        );

    while (my ($in, $out) = each(%footToolTipTests)) {
        last if $in eq 'STOP';

        it "should renumber footnotes for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "foot-notes renumbered";
    tie my %footRenumberTests => 'Tie::InsertOrderHash', (
            # 1
            "a [1]" => "a".mk_footnote(1)."",
            # in order
            "a [1] b[2]" => "a".mk_footnote(1)." b".mk_footnote(2)."",
            # various out of order
            "a [3] b[2] c[1]" => "a".mk_footnote(1)." b".mk_footnote(2)." c".mk_footnote(3)."",
            "a [3] b[1] c[2]" => "a".mk_footnote(1)." b".mk_footnote(2)." c".mk_footnote(3)."",
            "a [2] b[3] c[1]" => "a".mk_footnote(1)." b".mk_footnote(2)." c".mk_footnote(3)."",
            "a [2] b[1] c[3]" => "a".mk_footnote(1)." b".mk_footnote(2)." c".mk_footnote(3)."",
            "a [1] b[3] c[2]" => "a".mk_footnote(1)." b".mk_footnote(2)." c".mk_footnote(3)."",
        );

    while (my ($in, $out) = each(%footRenumberTests)) {
        last if $in eq 'STOP';

        it "should renumber footnotes for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(qw(chunk footnote)), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "footer-notes renumbered";
    tie my %footerRenumberTests => 'Tie::InsertOrderHash';
    # add footer to footRenumberTests
    while (my ($in, $out) = each %footRenumberTests) {
        my @foots = $in =~ m/\[(\d+)\]/g;
        my %renumber; @renumber{@foots} = sort {$a <=> $b} @foots;
        # warn wsEscape($in), Dumper(\@foots), Dumper(\%renumber); use Data::Dumper;

        # add footer to in
        $in .= "\n\n".join("\n", map {"[$_] footer$_"} sort {$a <=> $b} @foots);
        my $outn =0;

        # add title attrib
        foreach my $fn (@foots) {
            my $newN = $renumber{$fn};
            $out =~ s/(href='#footer-note-[^\d]+$newN'[^>]+)/$1 title='footer$fn'/
            }
        # add <p> & footer to out (re-ordered footer-number)
        $out = "<p>".$out."</p>\n\n".join("<br />\n", map {$outn++; mk_footernote($outn)." footer$_"} @foots);
        # vverbose 0,"rewrite $in => $out";
        $footerRenumberTests{$in} = $out;
        }

    while (my ($in, $out) = each(%footerRenumberTests)) {
        last if $in eq 'STOP';

        it "should renumber footer-notes for ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "footer-notes followed by paragraph";
    tie my %footerFollowedPTests => 'Tie::InsertOrderHash', (
            # footer, then p. NB: the footer is not followed by a \n\n, because you are being bad anyway
            "[1] footer\n\np1" => "".mk_footernote(1)." footer<br />\n<p>p1</p>",
        );

    while (my ($in, $out) = each(%footerFollowedPTests)) {
        last if $in eq 'STOP';

        it "should keep footer-notes followed by <p> in order".wsEscape("".$in);
            $it = BlogWiki->new($in);
            $out =~ s/\{BlogWiki::FootnotePrefix\}/$it->footnotePrefix/eg;
            is $it->html(), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

describe "http: auto-links";
    tie my %httpLinkTests => 'Tie::InsertOrderHash', (
            # Isolated
            "http://a.com/blah" => mk_link("http://a.com/blah"),
            # embedded
            "X http://a.com/blah Y" => "X ".mk_link("http://a.com/blah")." Y",
            # terminal punctuation stripped
            "http://a.com/blah." => mk_link("http://a.com/blah").".",
            "http://a.com/blah," => mk_link("http://a.com/blah").",",
            "http://a.com/blah. X" => mk_link("http://a.com/blah").". X",
            "http://a.com/blah, X" => mk_link("http://a.com/blah").", X",
            # terminal punct not stripped
            "http://a.com/blah/" => mk_link("http://a.com/blah/"),
            "http://a.com/blah/ X" => mk_link("http://a.com/blah/")." X",
        );

    while (my ($in, $out) = each(%httpLinkTests)) {
        last if $in eq 'STOP';

        it "should make http:... into <a> for: ".wsEscape("".$in);
            $it = BlogWiki->new($in);
            is $it->html('chunk'), $out, spec;
            # eq_or_diff $it->html, $out, spec;

        }

sub wsEscape {
    my ($text) = @_;

    %ws = (
        "\n" => '\n',
        "\t" => '\t',
        );
    $text =~ s/([\t\n\r])/$ws{$1}/eg;
    return $text;
    }

sub mk_footnote {
    my ($n, $title) = @_;
    return 
        "<a href='#footer-note-{BlogWiki::FootnotePrefix}$n' name='foot-note-{BlogWiki::FootnotePrefix}$n'"
        .(defined($title) ? " title='".escapeHTML($title)."'" : '')
        ."><sup>$n</sup></a>";
    }

sub mk_footernote {
    my ($n) = @_;
    return 
        "<a href='#foot-note-{BlogWiki::FootnotePrefix}$n' name='footer-note-{BlogWiki::FootnotePrefix}$n'>"
        ."[$n]</a>";
    }

sub mk_link {
    my ($href, $text) = @_;
    "<a href='$href'>".(escapeHTML($text) || $href)."</a>";
    }

1;
