package GroupBy::Parser::SpaceColumns;

=pod

Parses into space delimited columns. Default is 1,2,3,....

=cut

use Time::Local;
use Carp;
use Verbose;
$kVerbose=8;

sub columns
	{
	map {"column_$_"} qw(1 2 3 4...);
	}
	
sub defaultColumns {qw(1 2)}

sub can
	{
	my $self=shift;
	my ($method) = @_;
	
	if ($method =~ /makeNode_column_([0-9]+)/)
		{
		my $columnNum = $1;
		return sub {return shift->makeNode_column($columnNum,@_)};
		}
	elsif ($method =~/column_([0-9]+)/)
		{
		my $columnNum = $1;
		return sub {$self->column($columnNum)};
		}	
	}

sub column
	{
	my $self=shift;
	my ($columnNum) = @_;
	
	#vverbose 8,"col $columnNum = ",$self->{$columnNum},"\n";
	
	return $self->{$columnNum};
	}

sub makeNode_column
	{
	my $self=shift;
	my ($columnNum, $node) = @_;
	
	#my $x=$node;
	#confess;
	
	my $label = $self->column($columnNum);
	if (!defined $label) {return $node;}
	
	#vverbose 8,"node $columnNum=$label\n";
 
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	
	my $sortType = 'stringSortKey';
	$node->{$sortType} = $node->{'count'};
	
	#print "##"; use Data::Dumper; print Dumper($x);
	
	return $node;
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
		$self->{$k} = $v;
		}
		
	#print "",( map {$_." = ".$columns->{$_}."\n"} sort keys %$columns),"\n";
	}

sub parseLogLine
	{
	my $self=shift;
	my ($logLine) =@_;
	#print $logLine;
	#$_ = $logLine;
	
	my @elements= split(/ /,$logLine);
	
	#vverbose 8,"elements ",scalar @elements,"\n";
	
	my %columns;
	@columns{1..scalar @elements} = @elements;
	return \%columns;
	
	}

1;
