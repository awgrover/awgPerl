package JPilot::Datebook;
package JPilot::Datebook::Record; # for circular ref
    use Moose;
package JPilot::Datebook;
use Moose;
no warnings 'uninitialized';

=head1 JPilot::Datebook

An interface to JPilot's view of the palm database for the datebook. This is the
current state, merging the .pdb (the copy from the palm) and the .pc3 (the changes
made through the JPilot GUI).

    use JPilot::Datebook;

    $db = new JPilot::Datebook;

    foreach my $record (@{ $db->records }) {
        if ($entry->is_modified)
        if ($entry->is_deleted)
        if ($entry->is_new)
        ...
        $entry->{'day'} ... etc

        $entry->{'day'} = 9;
        $entry->update;
        }

    $newRecord = $db->new_Record;
    ...
    $newRecord->update;
    }

=cut

use Palm::PDB;
use Palm::Datebook;
use JPilot::PC3::Datebook;

=head2 Load()

A no-op. The Palm::PDB functionality of this is folded into records().
Which also means that all the ->{'attributes'} aren't available until
you after you call records(). This should probably change when other
database types are implemented in the future.

=cut

=head2 records()

Use this instead of ->{'records'}

You will see only 1 record per 'id', the newer JPilot's edit, or the original palm copy
if there were no edits.

The record is a subclass of JPilot::Datebook::Record.

=cut

has 'records', is => 'ro', builder => '_read_records', lazy => 1;
has 'pdb', is => 'rw';
has 'pc3', is => 'rw';

sub _read_records {
    my $self = shift;

    $self->pdb(Palm::PDB->new);

    my $dir = ($ENV{'JPILOT_HOME'} || $ENV{'HOME'})."/.jpilot";
    my $dbName = "$dir/DatebookDB.pdb";
    $self->pdb->Load($dbName);

    my %records = map { ($_->{'id'}, Palm::Datebook::Record->new($_)) } @{ $self->pdb->{'records'} };

    $self->pc3(JPilot::PC3::Datebook->new);
    foreach (@{ $self->pc3->records} ) {
        $records{$_->id} = $_;
        }

    return [sort { $a->id <=> $b->id } values %records];
    }

sub dump {
    my $self = shift || JPilot::Datebook->new;
    foreach my $entry (@{$self->records}) {
        print $entry->dump,"\n";
        }
    }

package JPilot::Datebook::Record;
use Moose;
no warnings 'uninitialized';

=head1 JPilot::Datebook::Record

A hash of the datebook data (as in Palm::Datebook->record), but with a few extra flags,
and convenience methods.

=cut

my @RecordFields = qw(year month other_flags end_minute description start_minute end_hour start_hour day id alarm);
foreach (@RecordFields) {
    has $_, is => 'rw';
    }

=head2 id() Convenience for the $record->{'id'}

=cut

sub id {
    shift->{'id'};
    }

=head2 is_modified Has been edited by JPilot

=head2 is_deleted Has been deleted (by JPilot)

=head2 is_new Has been created by JPilot or ->new

=cut

sub is_modified { undef }
sub is_deleted { undef }
sub is_new {my $self = shift; !( exists($self->{'id'}) && defined($self->{'id'}) ) }

sub startTime {
    my $self=shift;
    if ($self->{'start_minute'} == 255) {
        return "";
        }
    else {
        return sprintf "%.2d:%.2d", $self->{'start_hour'}, $self->{'start_minute'};
        }
    }
sub endTime {
    my $self=shift;
    if ($self->{'start_minute'} == 255) {
        return "";
        }
    else {
        return sprintf "%.2d:%.2d", $self->{'end_hour'}, $self->{'end_minute'};
        }
    }

sub rtName() {""}

=head2 dump() Formatted record

=cut

sub dump {
    my ($self) = @_;
    my $description = $self->{'description'};
    my $indent = " " x 60;
    $description =~ s/\n/\n$indent/gs;
    return sprintf "%9d %-20s %.4d-%.2d-%.2d %5s -> %5s (%s) %s", $self->id,$self->rtName,$self->{'year'},$self->{'month'},$self->{'day'},$self->startTime,$self->endTime,$self->{'when_changed'},$description;
    }


package Palm::Datebook::Record;
use Moose;
no warnings 'uninitialized';

use JPilot::Datebook;
extends 'JPilot::Datebook::Record';

sub BUILDS {
    my ($record) = $_;
    return $record;
    }
1;
