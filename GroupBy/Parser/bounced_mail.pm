package GroupBy::Parser::bounced_mail;
use Class::New;
@ISA=qw(Class::New);

=pod

Parses the bounced.mail log of my procmail bouncer.

=cut

use strict;
use Time::Local;
use Carp;
use Verbose;
$kVerbose=8;

use vars qw(%kProperties);
BEGIN { %kProperties = 
	(
	# assume type=>'histo', sort=>'text'
	date=>{type=>'ordered'},
	time=>{type=>'ordered'},
	mon=>{type=>'ordered',sort=>'numeric'},
	day=>{type=>'ordered',sort=>'numeric'},
	hour=>{type=>'ordered',sort=>'numeric'},
	min=>{type=>'ordered',sort=>'numeric'},
	year=>{type=>'ordered',sort=>'numeric'},
	rule=>{},
	from=>{},
	fromName=>{},
	fromAddress=>{},
	fromHost=>{},
	subject=>{},
	);
	}
sub _properties {map {"column_$_"} keys %kProperties }
	
use vars qw(%kDynamic);
%kDynamic = 
	(
	# assume type=>'histo', sort=>'text'
	fromDomain=>{},
	from2Domain=>{},
	subjectWords=>{},
	);

use vars qw(%kColumnInfo);
%kColumnInfo = (
	(map { ("column_$_"=>$kProperties{$_}) } keys %kProperties ),
	(map { ("column_$_"=>$kDynamic{$_}) } keys %kDynamic ),
	);
	
use Class::MethodMaker get_set=>[ _properties ];

sub columns
	{
	keys %kColumnInfo,
	}
	
sub defaultColumns {qw(date rule)}

#FIXME die?
sub columnTypes
	{
	my $self=shift;
	
	# text assumed
	my %types= map {($_,'text')} $self->columns;
	foreach (qw(mon day hour min))
		{
		$types{$_}='number';
		}
	return \%types;
	}
		
sub parse
	{
	my $class=shift;
	
	my ($logLine) = @_;
	confess ($class)," new() requires a logline" if !defined $logLine;

	my $self=$class->new;

	my $columns = $self->parseLogLine($logLine);
	
	return undef if !$columns;
	return $columns if !ref $columns;
	
	$self->argInit(%$columns);	

	return $self;
	}

sub makeNode
	{
	my $self=shift;
	
	my ($column, $node) = @_;
	

	my $label = $self->$column();
	#vverbose 8,"$column=$label\n";
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	
	my $colInfo = $kColumnInfo{$column};
	my $sortType = $colInfo->{'sort'} eq 'numeric' ? 'numericSortKey' : 'stringSortKey';
	my $sort2 = $colInfo->{'sort2'} eq 'numeric' ? 'secondary_numericSortKey' : 'secondary_stringSortKey';
	if ($colInfo->{'type'} eq 'ordered')
		{
		$node->{$sortType} = $label;
		}
	else
		{
		$node->{'numericSortKey'} = $node->{'count'};
		$node->{$sort2} = $label;
		}
	return $node;
	}

use vars qw(%kMonth);
@kMonth{qw(jan feb mar apr may jun jul aug sep oct nov dec)}=(1..12);

sub makeNode_column_date
	{
	my $self=shift;
	
	my $node=$self->makeNode('column_date',@_);
	
	my $monthOrd = $kMonth{lc($self->column_mon)};
	
	delete $node->{'stringSortKey'};
	$node->{'numericSortKey'} = 
		sprintf ("%04d%02d%02d" , $self->column_year,$monthOrd,$self->column_day);
	
	return $node;
	
	}
		
sub column_when {} #nop
sub makeNode_column_when
	{
	my $self=shift;
	
	my ($node) = @_;
	
	my $cn;
	my (@date) = map { $cn ="column_$_"; $self->$cn() } qw(mon day hour min);
	#print join(",",@date),"\n";

	
	my ($label, $unixTime);
	($label, $unixTime) = formatDate(@date[0]);
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $kMonth{lc($self->column_mon)};
	$node->{'elidable'} = 1;
	
	($label, $unixTime) = formatDate(@date[0,1]);
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $unixTime;
	$node->{'elidable'} = 1;

	($label, $unixTime) = formatDate(@date[0,1,2]);
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $unixTime;
	$node->{'elidable'} = 1;

	($label, $unixTime) = formatDate(@date[0,1,2,3]);
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $unixTime;
	$node->{'elidable'} = 0;
	
	return $node;
	}

sub column_fromDomain {} #nop
sub makeNode_column_fromDomain
	{
	my $self=shift;
	
	my ($node) = @_;
	
	my @dots = split(/\./,$self->column_fromHost);
	#vverbose 0,@dots,"\n";
	
	my ($label);
	foreach my $aDot (map {lc} reverse @dots)
		{
		$label = $label ? "$aDot.$label" : $aDot;
		
		$node->{'branches'}->{$label}->{'count'}++;
		$node = $node->{'branches'}->{$label};
		$node->{'numericSortKey'} = $node->{'count'};
		$node->{'secondary_stringSortKey'} = $label;
		$node->{'elidable'} = 1;
		}
	$node->{'elidable'} =0;
		
	
	return $node;
	}

sub column_from2Domain {} #nop
sub makeNode_column_from2Domain
	{
	# starts with first 2 elements of host name
	my $self=shift;
	
	my ($node) = @_;
	
	my @dots = split(/\./,$self->column_fromHost);
	my ($first, $second) = (pop @dots, pop @dots);
	push @dots, $second
		? "$second.$first"
		: $first;
	#vverbose 0,@dots,"\n";
	
	my ($label);
	foreach my $aDot (map {lc} reverse @dots)
		{
		$label = $label ? "$aDot.$label" : $aDot;
		
		$node->{'branches'}->{$label}->{'count'}++;
		$node = $node->{'branches'}->{$label};
		$node->{'numericSortKey'} = $node->{'count'};
		$node->{'secondary_stringSortKey'} = $label;
		$node->{'elidable'} = 1;
		}
	$node->{'elidable'} =0;
		
	
	return $node;
	}


sub column_subjectWords {} #nop
sub makeNode_column_subjectWords
	{
	my $self=shift;
	
	my ($baseNode) = @_;
	
	my @words = split(/[^a-zA-Z]/,$self->column_subject);
	#vverbose 0,@dots,"\n";
	
	my ($node);
	#$node=$baseNode;
	foreach my $label ( map {lc} grep {$_} @words)
		{
		$node = $baseNode;
		
		$node->{'branches'}->{$label}->{'count'}++;
		$node = $node->{'branches'}->{$label};
		$node->{'numericSortKey'} = $node->{'count'};
		$node->{'secondary_stringSortKey'} = $label;
		$node->{'elidable'} = 1;
		}
	$node->{'elidable'} =0;
		
	
	return $node;
	}

sub parseLogLine
	{
	my $self=shift;
	my ($logLine) =@_;
	#print $logLine;
	#$_ = $logLine;
	
	my %columns;
	
	@columns{qw(mon day time year)} = $logLine =~ /^[^ ]+ ([^ ]+) ([^ ]+) ([^ ]+) ([^ ]+)# \(/;
	my $remainder = $';
	
	if (!$columns{'mon'})
		{
		#vverbose 8,"reject: Not a date\n";
		return undef;
		}
	
	#vverbose 8,"hit: got a date\n";
	
	$columns{'date'} = join(" ",@columns{qw(year mon day)} );
	@columns{qw(hour min)} = $columns{'time'} =~ /(\d+):(\d+)/;
	
	( $columns{'rule'} ) = $remainder =~ /^([^)]+)\) /;
	$remainder = $';
	
	# parse FROM address
	my ($fromName, $fromAddress, $from, $subject);
	while (1)
		{
		$_=$remainder;
		
		# "blah" <addr@x.x>
		/^"([^"]*)" ?<([^>]*)>: / && do
			{
			$subject = $';
			$fromName = $1;
			$fromAddress = $2;
			last;
			};
		
		# blah <addr@x.x>
		/^([^<]*) ?<([^>]*)>: / && do
			{
			$subject=$';
			$fromName = $1;
			$fromAddress = $2;
			last;
			};
		
		# addr@x.x
		/^([^:]*): / && do
			{
			$subject=$';
			$fromName = "";
			$fromAddress = $1;
			last;
			};
		
		die "can't figure the email part '$remainder'";		
		}
		
	$from = $fromName
		? '"' . $fromName . '" ' . "<$fromAddress>"
		: $fromAddress;
	
	@columns{qw(fromName fromAddress from subject)} = ($fromName, $fromAddress, $from, $subject); 
		$remainder =~ /([^)]+)\) ([^:]*): (.*)/;
	( $columns{'fromHost'} ) = 	$fromAddress =~ /@(.*)/;
		


	my %columnLongName = map { ("column_$_",$columns{$_}) } keys %columns;
	return \%columnLongName;
	
	}

sub formatDate
	{
	my @dateParts = @_;
	my $str;
	$str = $dateParts[0] if scalar(@dateParts)> 0;
	$str .= ' '.$dateParts[1] if scalar(@dateParts)> 1;
	$str .= ' '.$dateParts[2] if scalar(@dateParts)> 2;
	$str .= ':'.$dateParts[3] if scalar(@dateParts)> 3;
	$str .= ":00" if scalar(@dateParts) == 3;
	#print "fmt = $str\n";

	my %months;
	@months{qw(jan feb mar apr may jun jul aug sep oct nov dec0)} = (0..11);
	my $month = $months{$dateParts[0]};
	my $day = @dateParts[1] || 1;
	my $unixTime = timelocal((0,@dateParts[3,2],$day,$month,101));



	return ($str,$unixTime);
	}

1;
