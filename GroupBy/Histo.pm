package GroupBy::Histo;

=pod

(see the gby script)

Invoke:
	histo [-p someModule [column...]] < file
e.g.
	histo -p ipfw date protocol toPort fromIP < /var/log/system.log

Variants:

histo < file
	Invoke with no arguments to parse by columns (space delimited), and groupBy col1,col2,...

histo -p <someModule> < file
	Invoke with no column list to get default groupBy ordering (dependant on module)


In fact, this is a generic groupBy, using the parsing modules (of -p
fame) to make sense of input. Write your own parsing modules for various data.
See GroupBy::Parser::SpaceColumns for the default. See GroupBy::Parser::ipfw for a more complex
example.

=cut

use strict;

use IO::File;
use Time::Local;

use Carp;
use Verbose;
$kVerbose=0;

use vars qw($kParser);
$kParser="GroupBy::Parser::SpaceColumns";	# default


sub main
	{
	
	if ($ARGV[0] eq '-p')
		{
		shift @ARGV;
		$kParser=shift @ARGV;
		$kParser = "GroupBy::Parser::$kParser" if ( $kParser !~/::/);
		vverbose 1,"parser=$kParser\n";
		eval "use $kParser"; die $@ if $@;
		}
	else
		{
		eval "use GroupBy::Parser::SpaceColumns"; die $@ if $@;
		}
	
	if ($ARGV[0] eq '-H' || $ARGV[0] eq '-h' || $ARGV[0] eq '-help' || $ARGV[0] eq '--help')
		{
		printHelp();
		}
	
	my @columns;
	
	if ($ARGV[0] eq '-a')
		{
		@columns = map {/column_(.*)/, $1} $kParser->columns();
		}
	else
		{			
		@columns = @ARGV;
		}

	@columns = $kParser->defaultColumns if (scalar @columns == 0);

	# read into objects
	my $ct = 0;
	my @entry;
	my ($e, $lastE);
	while (<STDIN>)
		{
		$e = $kParser->parse($_);
		if (!defined $e)
			{
			$lastE=undef;
			}
		elsif (!ref $e)
			{
			if ($lastE)
				{
				vverbose 8,"Repeat $e\n";
				for (my $i=0;$i < $e;$i++)
					{
					push @entry, $lastE;
					}
				}
			}
		elsif (ref $e)
			{
			push @entry, $e;
			$lastE=$e;
			#vverbose 8,$e->column_fromIP,"\n"
			}
		else
			{
			die "${kParser}->parse returned an odity '$e' for: $_";
			}

		$ct++;
		#last if $ct > 10;
		}
	
	vverbose 2,"## lines read=$ct\n";
		
	# run through list of histos (from command line)
	histo(\@entry, @columns);
	}

sub printHelp
	{
	print "Specify group-by columns:\n";
	foreach (sort $kParser->columns())
		{
		my ($basicName) = /column_(.*)/;
		print "\t",$basicName,"\n";
		}
	exit 0;
	}

sub histo
	{
	my ($entry, @columns) = @_;
	
	my %groupBy;
	my $from;
	my $node;
	my $label;
	my $addName;
	
	foreach my $anEntry (@$entry)
		{
		$label = 'Total Grouped by '.join(", ",@columns);
		$groupBy{$label}->{'count'}++;
		$node = $groupBy{$label};
		$node->{'stringSortKey'} = $node->{'count'};
		
		foreach my $column (@columns)
			{
			$addName = "column_".$column;
			
			die "not an object '$anEntry'" if !ref $anEntry;
			
			if ($anEntry->can($addName))
				{
				$node = makeNode($addName,$node, $anEntry);
				
				#vverbose 8,"got $column '$node'\n";
				}
			else
				{
				print "unknown column name: '$column'\n";
				printHelp();
				}
				
			}
				#use Data::Dumper;
				#print Dumper(\%groupBy);
				#die;

		}
	
	printHierarchy(\%groupBy);
	}
	
sub makeNode
	{
	# supports any column that is numeric
	my ($column, $node, $entry) = @_;
	
	#vverbose 8,"col=$column\n";
	my $method;
	if ($method = $entry->can("makeNode_$column"))
		{
		return $entry->$method($node);
		}
	elsif ($method = $entry->can('makeNode'))
		{
		return $entry->$method($column, $node);
		}
	
	my $label = "".$entry->$column();
	$node->{'branches'}->{$label}->{'count'}++;
	$node = $node->{'branches'}->{$label};
	$node->{'numericSortKey'} = $node->{'count'};
	return $node;
	}





=off

"byte 0"=>
	stringSortKey="  0"
	branches=>{...}
	count=>19

"208.  2. 13.128"=>
	numericSortKey="38"
	branches=>undef
	count=>38

=cut


sub printHierarchy
	{
	my ($hier, $indent) = @_;
	return if !defined $hier;
	
	my $distinct;
	my $distinctMsg;
	
	foreach my $k ( sortList($hier) )
		{
		$distinct = scalar keys %{$hier->{$k}->{'branches'}};
		if ($hier->{$k}->{'elidable'} && scalar keys %{$hier->{$k}->{'branches'}} == 1)
			{
			printHierarchy($hier->{$k}->{'branches'},$indent);
			}
		else
			{
			$distinctMsg = ($distinct > 1) ? "\t(distinct: $distinct)" : "";
			
			my $entries = $hier->{$k}->{'count'} > 1
				? " = entries:".$hier->{$k}->{'count'}
				: "";
			print "",("    " x $indent),$k,
				$entries,
				$distinctMsg, "\n";
			printHierarchy($hier->{$k}->{'branches'},$indent+1);
			}
		}
	}

sub sortList
	{
	my ($list) = @_;
	my $sortRez;
	return sort
		{
		$sortRez = 
		(defined $list->{$a}->{'numericSortKey'})
			? $list->{$b}->{'numericSortKey'} <=> $list->{$a}->{'numericSortKey'}
			: $list->{$b}->{'stringSortKey'} cmp $list->{$a}->{'stringSortKey'};

		if (!$sortRez && defined $list->{$a}->{'secondary_numericSortKey'})
			{
			$sortRez=
			$list->{$b}->{'secondary_numericSortKey'} <=> $list->{$a}->{'secondary_numericSortKey'}
			}
		elsif (!$sortRez && defined $list->{$a}->{'secondary_stringSortKey'})
			{
			$sortRez=
			$list->{$a}->{'secondary_stringSortKey'} cmp $list->{$b}->{'secondary_stringSortKey'}
			}

		$sortRez;
		}
		keys %$list
	;
	}
		
	
	
1;


