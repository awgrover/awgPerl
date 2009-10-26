package SCC::SCC::tla::Commands::init;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use Term::Menu;

use Verbose;
$kVerbose = $SCC::kVerbose;

our $MainBranch = 'main';

sub doCommand {
    my $self=shift;

    my ($archives,$default) = $self->sanityCheck();
    my %menuList = %$archives;
    my ($defaultLoc);
    if ($default) {
        $defaultLoc = delete $menuList{$default};
        }

    my $i=0;
    my $menu = Term::Menu->new(
        beforetext => 'Choose an archive location (exit and create one otherwise)',
        aftertext => 'Archive number '.($default ? "(0 for default)" : '').": ",
        tries => 3,
        );
    my $archive = $menu->menu(
        $default ? ($default => [ "* $default\t$defaultLoc" , $i++ ]) : (),
        map {
            ( $_ => [ "  $_\t".$menuList{$_} , $i++ ] )
            } sort keys %menuList
            );

    die "No choice" if ! defined $archive;

    print "Existing projects in $archive:\n";
    my $name = $self->menuChoice(
        "Choose existing project, or 'new'",
        "Project number",
        [ 'new',
            map { chomp; $_} `tla categories -A "$archive"`,
        ],
        'new',
        );
    if ($name eq 'new') {
        print "Choose a new project name: ";
        $name = <>; chomp $name;
        }

    print "Existing branches in $archive/$name:\n";
    my $branch = $self->menuChoice(
        "Choose existing branch, or 'new'",
        "Branch number",
        [ 'new',
            map { chomp; /--(.+)$/; $1} `tla branches -A "$archive" "$name"`,
        ],
        'new',
        );
    if ($branch eq 'new') {
        print "Starting branch [$MainBranch]: ";
        $branch = <>; chomp $branch;
        $branch = $MainBranch if $branch eq '';
        }

    my $fullName = "$name--$branch--1.0";
    print "$archive/$fullName\n";
    my ($version) = grep { /^$fullName$/} map { chomp; $_} `tla versions -A "$archive" "$name--$branch"`;
    if (!$version) {
        warn "creating archive\n";
        system("tla archive-setup -A \"$archive\" \"$fullName\"");
        }

    system("tla init-tree -A \"$archive\" \"$fullName\"");
    fixupTaggingMethod();
    system("tla import") if !$version; # force a "base" patch log, FIXME: detect this at "commit" time
    }

sub fixupTaggingMethod {
    my $fname = '{arch}/=tagging-method';
    my $FH = IO::File->new(">>$fname")
        || die "can't fixupTaggingMethod for $fname, $!";
    foreach ( 
            '',
            '# standard additions by awg',
            'source ^\.permissions\.?',
            'backup ^\..+\.sw[m-q]$',
            ) {
        print $FH $_,"\n";
        }
    }

sub sanityCheck {
    my $self=shift;

    my @id = map {chomp; $_} `tla my-id`;
    die 'You need to set your id with "tla my-id xxxx"' if !scalar(@id);

    my %archive;
    my $name;
    foreach (map {chomp; $_} `tla archives`) {
        if (s/^\s+//) {
            $archive{$name} = $_;
            }
        else {
            $name = $_;
            }
        }
    die 'You need to register some archive locations with "tla archive-register..."' if !scalar(%archive);

    my ($default) = map {chomp; $_} `tla my-default-archive`;
    warn "You might want to set a default archive location with 'tla my-default-archive'" if !$default;

    return (\%archive, $default);
    }

1;
