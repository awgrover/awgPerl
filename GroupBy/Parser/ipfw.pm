package GroupBy::Parser::ipfw;

=pod

Parses the /var/log/system.log of Darwin, looking for messages from ipfw.

=cut

use Time::Local;
use Carp;
use Verbose;
$kVerbose=4;

sub _columns {map {"column_$_"} (qw(date time rule protocol fromIP fromPort toIP toPort interface mon day hour min action direction))}

use Class::MethodMaker get_set=>[ _columns() ];

sub columns
	{
	(_columns(),
	map {"column_$_"} qw(fromIPBytes toIPBytes when)
	);
	}
	
sub defaultColumns {qw(date protocol toPort fromIP)}

sub columnTypes
	{
	my $self=shift;
	
	# text assumed
	my %types= map {($_,'text')} $self->columns;
	foreach (qw(rule fromPort toPort mon day hour min fromIPBytes toIPBytes))
		{
		$types{$_}='number';
		}
	return \%types;
	}
		
sub parse
	{
	my $class=shift;
	
	my ($logLine) = @_;
	confess (ref $self)," new() requires a logline" if !defined $logLine;

	my $self=$class->new;

	my $columns = $self->parseLogLine($logLine);
	
	return undef if !$columns;
	return $columns if !ref $columns;
	
	$self->hashInit($columns);	

	return $self;
	}

sub makeNode_base
	{
	# Sort by column-label
	my $self=shift;
	
	my ($column, $node) = @_;
	
	my $label = $self->$column();
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	
	my $sortType = $self->columnTypes->{$column} eq 'text' ? 'stringSortKey' : 'numericSortKey';
	$node->{$sortType} = $label;

	$node->{'secondary_numericSortKey'} = $node->{'count'};
	return $node;
	}

sub makeNode_column_time {return shift->makeNode_base('column_time',@_);}
sub makeNode_column_date {return shift->makeNode_base('column_date',@_);}
sub makeNode_column_min {return shift->makeNode_base('column_min',@_);}
sub makeNode_column_hour {return shift->makeNode_base('column_hour',@_);}
sub makeNode_column_day {return shift->makeNode_base('column_day',@_);}
sub makeNode_column_mon {return shift->makeNode_base('column_mon',@_);}

sub makeNode_column_toPort
	{
	my $self=shift;

	my ($node) = @_;
	
	return $self->_add_port($node, $self->column_toPort);	
	}
	
sub makeNode_column_fromPort
	{
	my $self=shift;
	
	my ($node) = @_;
	
	return $self->_add_port($node, $self->column_fromPort);	
	}
	
sub _add_port
	{
	my $self=shift;
	
	my ($node, $port) = @_;
	
	my $label = sprintf "port %-6s",$port;
	my $secondarySort = sprintf "%06d",$port;
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'}.$secondarySort;
	return $node;
	}

sub column_when {} #nop
sub makeNode_column_when
	{
	my $self=shift;
	
	my ($node) = @_;
	
	my (@date) = map { $cn ="column_$_"; $self->$cn() } qw(mon day hour min);
	#print join(",",@date),"\n";

	
	my ($label, $unixTime);
	($label, $unixTime) = formatDate(@date[0]);
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $unixTime;
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

sub column_fromIPBytes {} # nop
sub makeNode_column_fromIPBytes
	{
	my $self=shift;
	my ($node) = @_;
	
	return _add_IPByByte($node, $self->column_fromIP);	
	}
	
sub column_toIPBytes {} # nop
sub makeNode_column_toIPBytes
	{
	my $self=shift;
	my ($node) = @_;
	
	return _add_IPByByte($node, $self->column_toIP);	
	}

sub makeNode_column_fromIP
	{
	my $self=shift;
	my ($node) = @_;
	
	return _add_IP($node, $self->column_fromIP);	
	}
	
sub makeNode_column_toIP
	{
	my $self=shift;
	my ($node) = @_;
	
	return _add_IP($node, $self->column_toIP);	
	}
	
sub _add_IP
	{
	my ($node, $ip) = @_;
	
	my $label = formatIP($ip);
	my $secondaryLabel = numberIP($ip);	#FIXME: should be normalized to ~7digits, leading 0's
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'}.".".$secondaryLabel;
	return $node;
	}

sub _add_IPByByte
	{
	my ($node, $ip) = @_;
	
	my (@bytes) = split (/\./,$ip);
	
	my $label = formatIP(join(".",@bytes[0]));
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'};
	$node->{'elidable'} = 1;
	
	$label = formatIP(join(".",@bytes[0,1]));
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'elidable'} = 1;
	$node->{'numericSortKey'} = $node->{'count'};

	$label = formatIP(join(".",@bytes[0,1,2]));
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'};
	$node->{'elidable'} = 1;

	$label = formatIP(join(".",@bytes[0,1,2,3]));
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'};
	$node->{'elidable'} = 0;
	
	return $node;
	}

sub numberIP
	{
	my ($address) =@_;
	my @bytes = split(/\./,$address);

	my $value=0;
	foreach (@bytes)
		{
		$value = $value * 256 + $_;
		}

	return $value;
	}

sub formatIP
	{
	my ($ip) = @_;
	
	my @bytes = split(/\./,$ip);
	return sprintf "%03s.%03s.%03s.%03s",@bytes;
	}
		
sub new
	{
	my ($class) = shift @_;
	my $self = bless {}, $class;
	return $self->init(@_);
	}

sub init
	{
	my $self=shift;

	return $self;
	}

sub hashInit
	{
	my $self=shift;
	my ($columns) = @_;
	
	while (my ($k,$v) = each %$columns)
		{
		$self->$k($v);
		}
		
	#print "",( map {$_." = ".$columns->{$_}."\n"} sort keys %$columns),"\n";
	}

sub parseLogLine
	{
	my $self=shift;
	my ($logLine) =@_;
	#print $logLine;
	#$_ = $logLine;
	
	if ($logLine =~ /last message repeated (\d+) times/)
		{
		vverbose 8,"repeat $1\n";
		return $1;
		}
			
	my ($date, $time, $rule, $action, $protocol) =
		$logLine =~ /^(\w+ +\d+) ([^ ]+) [^ ]+ mach_kernel: ipfw: (\d+) (\S+) ([A-Z]+)/;

	if (!$date)
		{
		vverbose 8,"reject: Not a date\n";
		return undef;
		}

	my $remainder = $';

	my $icmpPort;
	if ($protocol eq 'ICMP' || $protocol eq 'P')
		{
		($icmpPort) = $remainder =~ /^:(\S+)/;
		$remainder = $';
		}

	my ($fromIP, $fromPort, $toIP, $toPort, $direction, $interface) =
		$remainder =~ /^ ([^:]+)(?::(\d+))? ([^:]+)(?::(\d+))? (in|out) via (\w+)/;
#	my ($date, $time, $rule, $action, $protocol, $icmpPort, $fromIP, $fromPort, $toIP, $toPort, $interface) =
#	my ($date, $time, $rule, $action, $protocol, $icmpPort, $fromIP, $fromPort, $toIP, $toPort, $interface) =
#		$logLine =~ /^(\w+ +\d+) (.+) localhost mach_kernel: ipfw: (\d+) (Deny|Count) ([^ ]+) ([^:]+)(?::(\d+))? ([^:]+)(?::(\d+))? in via (\w+)/;

	if ($icmpPort)
		{
		$toPort = $fromPort = $icmpPort;
		}

	my ($mon, $day) = $date =~ /(\w+) +(\d+)/;
	my ($hour, $min) = $time =~ /^(\d\d):(\d\d)/;

	my %columns;
	@columns{qw(column_date column_time column_rule column_action column_protocol column_fromIP column_fromPort column_toIP column_toPort column_interface column_direction)} =
		($date, $time, $rule, $action, $protocol, $fromIP, $fromPort, $toIP, $toPort, $interface, $direction);
	@columns{qw(column_mon column_day column_hour column_min)} = ($mon, $day, $hour, $min);

	return \%columns;
	
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
