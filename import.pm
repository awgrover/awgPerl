package import;
use strict; use warnings; no warnings 'uninitialized';

use Callers;
use Carp;
use Data::Dumper; use Verbose;

# use Import qw($Some::Package::var &X::y %A::hash)
# That symbol is now aliased into your package.
# NB: only by that sigil, e.g. proc, scalar, hash!

sub import {
    my $me = shift;
    # my (@names) = @_;

    my $targetModule = Callers::importerClass();
    confess "Couldn't figure out the target module" if !$targetModule;

    foreach my $name (@_) {
        my ($sourceModule, $symbolName) = $name =~ /.(.+)::([^:]+)$/;
        croak "Argument(s) to: use import qw(...), expected to be qualified (with '::') names. Saw $name" if !$symbolName;
        my ($sigil, $sigillessName) = $name =~ /^([\$&%])(.+)/;
        croak "Argument(s) to: use import qw(...), expected to have a sigil. Saw $name" if !$sigil;

        my $alias = $targetModule."::".$symbolName;
        my $type = { '%' => 'HASH', '$' => 'SCALAR', '&' => 'CODE', '@' => 'ARRAY' }->{$sigil};
        if ($type eq 'CODE') {
            croak "Argument(s) to: use import qw(...), package expected to already exist. Saw $name" 
                if ! eval "scalar(\%$sourceModule\::)";
            }
        else {
            croak "Argument(s) to: use import qw(...), expected to already exist in 'home' package. Saw $name" 
                if ! eval "exists(\$$sourceModule\::\{$symbolName})";
            croak "Argument(s) to: use import qw(...), expected to already exist in 'home' package. Saw $name" 
                if ! eval "defined *$sigillessName\{$type}";
            }

        my $x = "my \$y = \\$name; *$alias = \\$name;";
        # my $x = "warn keys(*$sigillessName)";
        # my $x = "*$alias"."{$type} = *$sigillessName"."{$type}; warn 'eval $name ',\\$name";
        no strict 'refs';
        eval $x;
        confess "Internal, tried to alias using: $x.\n $@" if $@;
        use strict 'refs';
        }
    }

1;
