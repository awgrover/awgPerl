#!/usr/bin/env perl
# --- template-file-source
# OR
# use cutnpaste_template;
# render("some template...", {some => $data...});
#
# See __DATA_ section for syntax of template
# version 2: supports escaping the sigils
# version 3: supports catenation, $_ in iteration, and $0..$9 for arrays

use strict; use warnings; no warnings 'uninitialized';
use Text::Balanced qw(extract_bracketed);
sub render {
    my ($template, $data) = @_;

    my @rez;
    # 1st iteration: head@name[block]rest...
    # $template = "rest" for next split
    # Split gives just "head" if no "@", so processes each piece
    # avoid $' with a split
    while (my @repeats = split(/(?(?<=[^\\])|^)@([a-zA-Z]\w*|_)(?=\[)/, $template,2)) {
        # interpolates the scalars in the "head" piece
        $repeats[0] =~ s/(?(?<=[^\\])|^)\$([a-zA-Z]\w*|_|[0-9])/(index('0123456789',$1) >= 0) ? $data->{'_'}->[$1] : $data->{$1}/eg;
        push @rez, $repeats[0];
        last if ! $repeats[1];

        my $field_name = $repeats[1];
        # warn "During '\@$field_name'";

        # Get the "block" and "rest"
        my $bracketed;
        ($bracketed, $template) = extract_bracketed( $repeats[2], '[');
        $bracketed =~ s/^\[//;
        $bracketed =~ s/\]$//;

        # Repeat the block
        my $list = (ref($data->{$field_name}) eq 'ARRAY') ? $data->{$field_name} : [$data->{$field_name}];
        # warn "To repeat '\@$field_name', ".@$list." times";
        foreach my $sub_data ( @$list ) {
            # recurse on this block with our block's data
            # warn "\tWith $sub_data ",(ref($sub_data) eq 'ARRAY' && @$sub_data);
            push @rez, render( $bracketed, {%$data, (ref($sub_data) eq 'HASH' ? %$sub_data : ()), '_' => $sub_data});
            }
        # warn "Finished:'\@$field_name'";
        }

    join("",@rez);
    }

package cutnpaste_template_runner;

use strict; use warnings; no warnings 'uninitialized';

use File::Basename;
use IO::File;
use Data::Dumper;

sub main {
    my $template;
    if (-e $ARGV[0]) {
      $template = join("",<>);
      }
    else {
      $template = join("",<DATA>);
      }

    my %data;
    
    $data{'file'} = (-e $ARGV[0]) ? basename($ARGV) : "__DATA__ section";
    $data{'name'} = "'Toplevel ".$data{'file'}."'";
    $data{'has_dollar_in_value'}='<this interpolation has a dollar sign: $not_reinterpolated>';
    $data{'outer'} = [
      { name => 'block 1', outerValue => 'block1-outer',
        inner => [{ name => 'inner1.1'},{ name => 'inner1.2'}],
        },
      { name => 'block 2', outerValue => 'block2-outer',
        inner => [{ name => 'inner2.1'},{ name => 'inner2.2'}],
        }
      ];
    $data{'lol'} = [ # list-of-lists
      [qw(1 2 3)],
      [qw(a b c $no_recursive_interpolation_of_data)],
      ];

    print main::render($template, \%data);
    }
main() if $0 eq __FILE__;
1;

__DATA__
Test Template
Interpolates only "names" following @ and $, these don't work: @123 @123dog @["dog" xx] $"dog"
Iterates a block: \@something[ stuff repeated ]
Within an iteration, also iterpolates \$_ and \$0..\$9 (see below)
Must otherwise balance left and right [] in iterations so the \@xxx[...] works

Literal @ and literal $ (because no "word" after sigil)
Escape dollar-sign: \$name
Escape at-sign \@outer[]
Escape un-balanced brackets \] \[ (especially inside iterations)
Catenate interpolation: pretend scalar is array: Prefix@name[$_]Suffix
Can't escape backslash \\@outer[]
No re-interpolation: $has_dollar_in_value

Top level scalar interpolation of \$file: $file
Top level name: $name

Iterate, as if foreach (@{\$data->{'outer'}}) {render(..)} : @outer[
  Level1 $name
    Also, \$_ is set to the each: $_
    Unbalanced \] and \[ must be escaped, but [ balanced ] ones are fine
    Top-level value visible: file=$file
    Level1 name overrides top-level: $name
    Level1 outerValue: $outerValue
    Starting inner list:
    @inner[Inner $name
      Level2 name overrides level1: $name
      Top-level values still visible: file=$file
      Level1 value visible: outerValue=$outerValue
    end-of-inner]
  end-of-Level1
  ]

If a list holds lists, you can index the inner with \$0..\$9
List of lists @lol[
  Elements of array $_
    \$0 = $0
    \$2 = $2 
    \$n does catenate in an iteration, but that's deprecated: $0Catenated
    balanced brackets cause no problems: [ x ]
    And, you can simply get the elements of a list: @_[ $_ ]]
    (Note the "\$no_recursive_interpolation_of_data" value above)
end lol

Terminal $name text
