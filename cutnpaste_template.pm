#!/usr/bin/env perl
use strict; use warnings; no warnings 'uninitialized';

# --- template-file-source

use File::Basename;
use IO::File;
use Text::Balanced qw(extract_bracketed);
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
    $data{'outer'} = [
      { name => 'block 1', outerValue => 'block1-outer',
        inner => [{ name => 'inner1.1'},{ name => 'inner1.2'}],
        },
      { name => 'block 2', outerValue => 'block2-outer',
        inner => [{ name => 'inner2.1'},{ name => 'inner2.2'}],
        }
      ];

    print render($template, \%data);
    }

sub render {
    my ($template, $data) = @_;
    # replace $x with $data->{'x'}
    # replace @x[...] with foreach my $x (@{$data->{'x'}}) { ... }

    # repeats, 1st, recurse
    my @rez;
    # this split could probably be a match...
    while (my @repeats = split(/@(\w+)(?=\[)/, $template,2)) {
        push @rez, $repeats[0];
        last if ! $repeats[1];
        my $field_name = $repeats[1];
        # warn "During '\@$field_name'";
        my $bracketed;
        ($bracketed, $template) = extract_bracketed( $repeats[2], '[');
        $bracketed =~ s/^\[//;
        $bracketed =~ s/\]$//;
        # warn "To repeat '\@$field_name', ".@{$data->{$field_name}}." times";
        foreach my $sub_data ( @{$data->{$field_name}} ) {
            # recurse on this block with our block's data
            push @rez, render( $bracketed, {%$data, %$sub_data});
            }
        # warn "Finished '\@$field_name'";
        }

    # warn "Finished repeats ".@rez;
    my $rez = join("",@rez);

    # scalars
    $rez =~ s/\$(\w+)/$data->{$1}/eg;

    return $rez;
    }

main();

__DATA__
Test Template
Top level scalar interpolation of the filename: $file
Top level name: $name
Can't escape dollar-sign: \$name
Can't escape at-sign \@outer[]
Can escape left-bracket \[
Literal @
Must otherwise match left and right []
Repeating block:
  @outer[top-of-block
    Top-level values still visible, filename: $file
    Block's name (hiding top-level name): $name
  end-of-block]
Nested Block
  Top name: $name
  @outer[Outer
    Outer name: $name   
    Outer visible value (outerValue): $outerValue
    Starting inner on this line: @inner[Inner
      Outer visible value (outerValue): $outerValue
      Inner name: $name
    end-of-inner]
  end-of-outer]
