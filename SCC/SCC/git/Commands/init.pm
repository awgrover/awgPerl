package SCC::SCC::git::Commands::init;
use base qw(SCC::BaseSCCCommand SCC::Util);

use strict;
use warnings; no warnings 'uninitialized';

use Cwd;
use Term::Menu;
use SH;
use File::Basename;
use IO::Dir;
use File::Temp;

use Verbose;
$kVerbose = $SCC::kVerbose;

sub doCommand {
    my $self=shift;

    $self->preSanity;

    my $cacheUpdateType = $self->menuChoice(
        "Update git-url cache?",
        "Branch number",
        { again => 'same as last update (defaults to '.$ENV{'HOME'}." dirs)",
            home => 'Only '.$ENV{'HOME'}." dirs",
            all => 'All .git dirs that locate can find',
            cache => "Don't update, use last cache",
        },
        'cache',
        );

    my @urls;

    vverbose 0,"cacheUpdateType $cacheUpdateType";
    if ($cacheUpdateType eq 'cache') {
        @urls = sort (map {chomp; $_} `git config -f ~/.git.setup/git-config --get-all urlcache.remote`);
        }
    else {
        my $prefix='';
        if ($cacheUpdateType eq 'again') {
            ($cacheUpdateType) = `git config -f ~/.git.setup/git-config --get urlcache.searchtype`;
            chomp $cacheUpdateType;
            vverbose 0,"last cacheUpdateType $cacheUpdateType";
            $cacheUpdateType = 'home' if !$cacheUpdateType;
            }

        system('git config -f ~/.git.setup/git-config urlcache.searchtype '.SH::quote($cacheUpdateType));
            
        if ($cacheUpdateType eq 'home') {
            $prefix = SH::quote($ENV{'HOME'})."'/.*/'";
            }

        my $cmd = 
            "locate -r $prefix'\.git/config\$' "
            ."| xargs -n 1 -i git config -f {} --get-regexp 'remote\..*\.url'"
            ."| awk '{print \$2}'"
            ."|sort -u"
            ;
        vverbose 0,"$cmd";

        @urls = sort (map {chomp; $_} `$cmd`);

        system('git config -f ~/.git.setup/git-config --unset-all urlcache.remote');
        foreach (@urls) {
            system('git config -f ~/.git.setup/git-config --add urlcache.remote '.SH::quote($_));
            }
        }

    my $cloneUrl = $self->menuChoice(
        "Clone from: ",
        "url",
        [ 
            'none',
            'other',
            @urls,
        ],
        0,
        );
    if ($cloneUrl eq 'none') {
        $cloneUrl = '';
        }
    elsif ($cloneUrl eq 'other') {
        print "url of existing: ";
        $cloneUrl = <>; chomp $cloneUrl;
        }

    if ($cloneUrl) {
        noExtantFiles();
        $self->gitclone($cloneUrl);
        }
    else {
        gitinit();
        }

    postSanityCheck();
    }

sub gitclone {
    my ($self, $cloneUrl) = @_;
    $cloneUrl = SH::quote($cloneUrl);
    vverbose 0,"clone from $cloneUrl";
    my $tmpName = ".tempWorkingDir.$$";
    vverbose 0,"temp dir $tmpName";
    system("git clone $cloneUrl ".SH::quote($tmpName));
    system("mv $tmpName/* $tmpName/.* .");
    unlink $tmpName;
    }

sub preSanity {
    my @problems;
    die "Error: a .git file/dir exists (rename/move it)" if -e ".git";
    }

sub noExtantFiles {
    my @extantFiles;
    my $dh = IO::Dir->new(".");
    while ($_ = $dh->read) {
        next if /^\.\.?$/;
        push @extantFiles, $_;
        }
    die "Error: extant files before the checkout (rename/move them)" if scalar @extantFiles;
    }

sub gitinit {
        system('git init');
        my @defaults = map {chomp; /^([^=]+)=(.+)/; [$1,SH::quote($2)]} `git config -f ~/.git.setup/git-config -l | grep -v urlcache.remote`;
        foreach (@defaults) {
            my ($k,$v) = @$_;
            system("git config $k $v")
                && die "Failed: git config $k $v";
            }
        }

sub postSanityCheck {
    my $self=shift;

    # will use $GIT_AUTHOR_EMAIL || $GIT_COMMITTER_EMAIL || $EMAIL too
    system('git config user.email > /dev/null 2>&1') 
        && warn "You should set your email: git config -f ~/.gitconfig user.email 'something'\n";

    # will use $GIT_AUTHOR_NAME || $GIT_COMMITTER_NAME too
    system('git config user.name > /dev/null 2>&1') 
        && warn "You should set your name: git config -f ~/.gitconfig user.name 'something'\n";

    my ($excludeFile) = map {chomp; $_} `git config core.excludesfile`;
    warn "You probably want to setup a default 'ignore' file: $excludeFile (see 'man gitignore')"
        if ! -f $excludeFile;
    }

1;
