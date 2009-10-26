package SH;
# some utils for "shell"

sub quote {
    # return a string that is shell-quoted (i.e. specials quoted/escaped)
    my ($str) = @_;

    # I'll wrap in single-quote, because then I only have to escape other single-quotes
    $str =~ s/'/'\\''/g;
    return "'$str'";
    }
1;
