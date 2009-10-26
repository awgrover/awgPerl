#!/usr/bin/env perl
package JPilot::PC3::Datebook;

=head1 JPilot::PC3::Datebook

Read the JPilot datebook.pc3 database, like Palm::Datebook.

The JPilot .pc3 databases are the modifications that the
JPilot app has made to the palm data. JPilot has a copy 
of the last sync of the .pdb. Thus, the .pc3 records
modifications, deletions, and additions.

This package provides an interface to the .pc3 of the datebook.

The environment variable JPILOT_HOME is used to find the .jpilot directory,
where the datebook file is (default is $HOME).

We look something like the Palm::Datebook object, but .pc3's don't have
all the same things as a .pdb (e.g. sort-blocks, etc.), and we provide some extra
behavior on the "record" (a JPilot::PC3::Datebook::Record).

    my $db = JPilot::PC3::Datebook->new;
    foreach my $entry (@{$db->records}) {
        if ($entry->is_modified)
        if ($entry->is_deleted)
        if ($entry->is_new)
        ...
        $entry->{'day'} ... etc
        }

From the command line,
    perl JPilot/PC3/Datebook.pm
is equivalent to
    perl -mJPilot::PC3::Datebook -e 'JPilot::PC3::Datebook::dump'

=cut

use Moose;
no warnings 'uninitialized';

use Verbose;
use Data::Dumper;
use Palm::Datebook;
use IO::File;
use Fcntl ':flock';

my $LEN_RAW_DB_HEADER = 78;
my $Next_id_version = 'version2';

has 'records', is => 'ro', builder => '_read_records', lazy => 1;

=head2 new()

Finds, and opens the datebook.pc3. Returns a JPilot::PC3::Datebook object.

=cut

sub BUILDARGS {
    return {};
    }


=head2 records()

Returns the records, which look like Palm::Datebook's records, plus some flags.

Note that we don't return all the records. It appears that a record (identified by the 'id')
can appear more than once in a .pc3, earlier entries superseded by later ones. We return only the last appearance of that 'id'.

=cut

sub _read_records {
    my $self = shift;
    vverbose 0,"READ $self";
    my $db = $self->open("<");

    my %records;
    # since "new" reads the record, and we have to use sys*, we detect done by id undef
    while ((my $db_entry = JPilot::PC3::Datebook::Record->new($self,$db))->id) {
        # vverbose 0,"read: ",Dumper($db_entry);
        # Apparently, the pc3 can have a series of deltas for a record,
        # e.g. 'modified', 'replaced'.... We'll use the last
        $records{$db_entry->{'id'}} = $db_entry;
        }
    $db->close;

    vverbose 0,"Read ",scalar(values %records)," entries";
    return [sort { $a->id <=> $b->id } values %records];
    }

sub filename {
    my $self=shift;
    my ($filename) = @_;
    my $dir = ($ENV{'JPILOT_HOME'} || $ENV{'HOME'})."/.jpilot";
    return $filename ? "$dir/$filename" : "$dir/DatebookDB.pc3";
    }

sub open {
    my $self=shift;
    my ($direction, $filename) = @_;

    my $dbName = $self->filename($filename);
    vverbose 0,"open $direction$dbName as $self";
    my $db = IO::File->new($direction.$dbName);
    $db || die "can't open $dbName for $direction, $!";

    flock $db,LOCK_EX;

    return $db;
    }

sub insert {
    my $self=shift;
    my ($new) = @_;

    vverbose 0,"get records again";
    push @{ $self->records }, $new;
    vverbose 0,"after insert: ",$self->dump;
    }
    
sub dump {
    my $self = shift || JPilot::PC3::Datebook->new;
    foreach my $entry (@{$self->records}) {
        print $entry->dump,"\n";
        }
    }

sub nextID {
    my $self=shift;
    # put in package JPilot::PC3;
    my $fh = $self->open("+<",'next_id');

    my $version = <$fh>;
    chomp $version;
    die "Wrong version '$version' for ".$self->name.", expected '$Next_id_version'" if $version ne $Next_id_version;
    my $idPos = tell($fh);

    my $nextID = <$fh>;
    chomp $nextID;
    die "Expected a number as second line of ".$self->name.", found '$nextID'" if $nextID !~ /^\d+$/;

    $nextID++;
    seek $fh,$idPos,0;

    print $fh $nextID,"\n";
    $fh->close;


    vverbose 0,"next id '$nextID'";
    return $nextID;
    }

=head2 update()

Re-writes the entire pc3 file, updating the elements from ->records(), 
and inserting new records.

=cut

sub update {
    my $self=shift;
    vverbose 0,"WRITE ".@{ $self->records }." records";
    my $dbh = $self->open(">");
    foreach my $record (@{ $self->records }) {
        print $dbh $record->pack();
        }
    $dbh->close;
    }

package JPilot::PC3::Datebook::Record;
use Moose;
no warnings 'uninitialized';

use JPilot::Datebook;
extends 'JPilot::Datebook::Record';

use Data::Dumper;

=head1 JPilot::PC3::Datebook::Record

Can be used like a Palm::Datebook hash (e.g. $record->{'day'}), but knows it came from
a JPilot::PC3::Datebook, and has a few extra flags.

=cut

has 'container',is => 'rw', isa => 'JPilot::PC3::Datebook';
has 'header', is => 'rw';

my $HEADER_VERSION = 2;
my %RtToName = (
    100 => 'PALM_REC',
    101 => 'MODIFIED_PALM_REC',
    102 => 'DELETED_PALM_REC',
    103 => 'NEW_PC_REC',
    104 => 'DELETED_PC_REC',
    105 => 'DELETED_DELETED_PALM_REC',
    106 => 'REPLACEMENT_PALM_REC',
    );
my %NameToRt; @NameToRt{values %RtToName} = keys %RtToName;

=h2 new($JPilot_PC3_Datebook, $open_pc3_file)

Initializes self from the next record in the .pc3 file. Called by JPilot::PC3::Datebook->records.

=h2 new($JPilot_PC3_Datebook)

Needs its fields to be set. Can be added to a .pc3 file.

    my $pc3 = JPilot::PC3::Datebook->new;
    my $event = JPilot::PC3::Datebook::Record->new;
    $event->{'day'} = 4;
    ...
    # signal intent to really include this
    $pc3->insert($event);
    # rewrite _all_ pc3 records
    $pc3->update;

=h2 container() returns the JPilot::PC3::Datebook object.

=cut

sub BUILDARGS {
    my $class = shift;
    my ($pc3, $dbh) = @_;

    my %properties = ( container => $pc3, header => {});
    my $entry;

    if ($dbh) {
        my $header;
        ($header,$entry) = read_record($dbh);
        $properties{'header'} = $header;
        }
    else {
        my %x = %{ new Palm::Datebook };
        $entry = \%x;
        $entry->{'unique_id'} = $pc3->nextID;
        $entry->{'id'} = $entry->{'unique_id'};
        $properties{'header'}->{'rt'} = $NameToRt{'NEW_PC_REC'};
        }

    @properties{keys %$entry} = values %$entry;
    return \%properties;
    }

sub read_record {
    my ($dbh) = @_;

    my $header_buff;
    my $header = {};
    my $ct = sysread $dbh, $header_buff, 4;
    return undef if $ct == 0;
    die "Needed 4 bytes, found $ct before eof" if $ct != 4;
    $header->{'header_len'} = unpack ("N", $header_buff);
    die "header_len (".$header->{'header_len'}.") longer than 255" if $header->{'header_len'} > 255;

    my @res;
    $ct = sysread $dbh, $header_buff, $header->{'header_len'}-4; 
    die "Needed ".($header->{'header_len'}-4)." bytes, found $ct before eof" if $ct != ($header->{'header_len'}-4);

    (@$header{qw(header_version rec_len unique_id rt attrib)},@res) = unpack ("N N N N C", $header_buff);
    die "header_version (".$header->{'header_version'}.") != $HEADER_VERSION" if $header->{'header_version'} != $HEADER_VERSION;
    # warn "unpacked: ",Dumper($header),join(", ",@res);

    my $buf;
    $ct = sysread $dbh, $buf, $header->{'rec_len'};
    die "needed ".$header->{'rec_len'}." bytes, found $ct" if $ct != $header->{'rec_len'};

    my $entry = Palm::Datebook::ParseRecord(undef, data => $buf);
    $entry->{'id'} = $header->{'unique_id'};

    # rt seems to be the PCRecType enum, e.g. NEW_PC_REC
    warn "unpacked: ",Dumper($header),"\n",Dumper($entry),"res: ",join(", ",@res);
    return ($header,$entry);
    }

=head2 rtName() Gives the mnemonic name for the .pc3 record_type flag

=cut

sub rtName { 
    my $self=shift;
    return $RtToName{$self->header->{'rt'}};
    }

=head2 startTime() Formatted start time "hh:mm"

=cut

=head2 insert()

Signals that this record should be written to the ->container() on ->container->update

NB: it won't be written until the update.

=cut

sub insert {
    my $self=shift;
    $self->container->insert($self);
    }

sub pack {
    my $self=shift;

    my $record = Palm::Datebook::PackRecord(undef, $self);
    $self->header->{'attrib'} = 0 if ! defined $self->header->{'attrib'};
    my $header_data = pack("NNNNC",$HEADER_VERSION,length($record),$self->id,$self->header->{'rt'},$self->header->{'attrib'});
    my $header_len = pack("N",length($header_data)+4);
    return $header_len.$header_data.$record;
    }

JPilot::PC3::Datebook::dump() if $0 eq __FILE__;

1;
