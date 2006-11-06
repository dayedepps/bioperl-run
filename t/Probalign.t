# -*-Perl-*-
## Bioperl Test Harness Script for Modules
## $Id$

use strict;
use vars qw($NUMTESTS);
BEGIN { 
    eval { require Test; };
    if( $@ ) {
	use lib 't';
    }
    use Test;
    $NUMTESTS = 10; 
    plan tests => $NUMTESTS; 
}

END { unlink qw(cysprot.dnd cysprot1a.dnd) }

use Bio::Tools::Run::Alignment::Probalign;
use Bio::AlignIO;
use Bio::SeqIO;
use Cwd qw(cwd);

use Bio::Root::IO;
use POSIX;

END {     
    for ( $Test::ntest..$NUMTESTS ) {
	skip("Probalign program not found. Skipping.",1);
    }
	unlink('probalign.log', 'probalign.out');
}

ok(1);

my @params = ();
my $factory = Bio::Tools::Run::Alignment::Probalign->new(@params);
my $inputfilename = Bio::Root::IO->catfile("t","data","cysprot.fa");
my $aln;

my $present = $factory->executable();
unless ($present && -e $present	) {
    warn "probalign program not found. Skipping tests $Test::ntest to $NUMTESTS.\n";
    exit(0);
}
my $version = $factory->version;
ok ($version >= 3.3, 1, "Code tested only on probalign versions > 3.3" );
$aln = $factory->align($inputfilename);
ok($aln);
ok( $aln->no_sequences, 7);

my $str = Bio::SeqIO->new('-file' => 
			  Bio::Root::IO->catfile("t","data","cysprot.fa"), 
			  '-format' => 'Fasta');
my @seq_array =();

while ( my $seq = $str->next_seq() ) {
    push (@seq_array, $seq) ;
}

my $seq_array_ref = \@seq_array;

$aln = $factory->align($seq_array_ref);
ok $aln->no_sequences, 7;
my $s1_perid = POSIX::ceil($aln->average_percentage_identity);
ok($s1_perid == 43 || $s1_perid == 44, 1,
   'diff versions of PROBALIGN have different vals');

my $cwd = cwd;
my $outfile = Bio::Root::IO->catfile($cwd,'probalign.out');
# add some more params
@params = ('-outfile_name'      => $outfile);
$factory = Bio::Tools::Run::Alignment::Probalign->new(@params);
$aln = $factory->align($seq_array_ref);
ok $aln->no_sequences, 7;
$s1_perid = POSIX::ceil($aln->average_percentage_identity);
ok($s1_perid == 43 || $s1_perid == 44, 1,
   'diff versions of PROBALIGN have different vals');


$inputfilename = Bio::Root::IO->catfile("t","data","cysprot1a.fa");
$aln = $factory->align($inputfilename);
ok $aln->no_sequences, 3;
$s1_perid = POSIX::ceil($aln->average_percentage_identity);

ok($s1_perid == 41 || $s1_perid == 42, 1,
   'diff versions of PROBALIGN have different vals');