package DoCommand;
use base qw(Exporter);
@EXPORT = qw(doCommand);

use strict;
use IO::File;
use Verbose;
$kVerbose = 0;


sub doCommand
	{
	my ($cmd) = @_;

	vverbose 6,"$cmd...\n";
	my $FH = IO::File->new("($cmd) 2>&1|");
	if (!$FH)
		{
		$! =  "Couldn't open $cmd|, $!";
		return undef;
		}
		
	my @rez = <$FH>;
	vverbose 10,"result line ct ",scalar(@rez),"\n";
	my $closed = $FH->close; my $dieLine = __LINE__;

	if (!$closed && wantarray())
		{
		vverbose 10,"Failed (cont.): ",join("\n",@rez),"\n";
		$! =join("",@rez);
		chomp $!;
		return undef;
		}
	elsif (!$closed)
		{
		vverbose 6,"Failed: ",join("\n",@rez),"\n";
		$@ = "$cmd\n\t".join("",@rez);;
		chomp $@;
		return undef;
		}

	vverbose 6,"\tsucceed $cmd\n";
	return wantarray() ? (\@rez,undef) : \@rez;
	}

1;
