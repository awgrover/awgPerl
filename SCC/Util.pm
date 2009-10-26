package SCC::Util;

use strict;
use warnings; no warnings 'uninitialized';

use Verbose;
$kVerbose = $SCC::kVerbose;


sub menuChoice {
    my $self=shift;
    my ($heading,$prompt,$choices, $default) = @_;
    # choices can be:
    #   a list: the answer is the choice
    #   a hash: the choice is the value, the answer is the key

    # force to hash
    if (ref($choices) eq 'ARRAY') {
        $choices = { map { ($_ => $_) } @$choices};
        }


    my ($defaultText);
    if ($default) {
        $defaultText = delete $choices->{$default};
        }
    my $i=0;
    my $menu = Term::Menu->new(
        beforetext => $heading,
        aftertext => $prompt.(defined($default) ? " (0 for default)" : '').": ",
        tries => 3,
        );
    my $answer = $menu->menu(
        $default ? ($default => [ "* $defaultText" , $i++ ]) : (),
        map {
            ( $_ => [ "  ".$choices->{$_} , $i++ ] )
            } sort keys %$choices
            );
    die "No choice" if ! defined $answer;
    return $answer;
    }

1;
