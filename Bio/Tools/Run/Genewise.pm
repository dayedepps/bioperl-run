#
# Cared for by
#
# Copyright to a FUGU Student Intern
#
# You may distribute this module under the same terms as perl itself
# POD documentation - main docs before the code

=head1 NAME

Bio::Tools::Run::Genewise - Object for predicting genes in a
given sequence given a protein

=head1 SYNOPSIS

  # Build a Genewise alignment factory
  my  $factory = Bio::Tools::Run::Genewise->new();

  # Pass the factory 2 Bio:SeqI objects (in the order of query peptide and
     target_genomic)
  # $genes is a Bio::SeqFeature::Gene::GeneStructure object  
  my $genes = $factory->predict_genes($seq1, $seq2);
  
  Available Params
  Model    [-codon,-gene,-cfreq,-splice,-subs,-indel,-intron,-null]
  Alg      [-kbyte,-alg]
  ..cont  [-gff,-gener,-alb,-pal,-block,-divide]
  Standard [-help,-version,-silent,-quiet,-errorlog]

=head1 DESCRIPTION

Genewise is a gene prediction program developed by Ewan Birney
http://www.sanger.ac.uk/software/wise2.

=head1 FEEDBACK

=head2 Mailing Lists

User feedback is an integral part of the evolution of this and other
Bioperl modules. Send your comments and suggestions preferably to one
of the Bioperl mailing lists.  Your participation is much appreciated.

  bioperl-l@bioperl.org          - General discussion
  http://bio.perl.org/MailList.html             - About the mailing lists
d2 Reporting Bugs

Report bugs to the Bioperl bug tracking system to help us keep track
 the bugs and their resolution.  Bug reports can be submitted via
 email or the web:

  bioperl-bugs@bio.perl.org
  http://bio.perl.org/bioperl-bugs/

=head1 AUTHOR - FUGU Student Intern

Email: fugui@worf.fugu-sg.org

=head1 APPENDIX

The rest of the documentation details each of the object
methods. Internal methods are usually preceded with a _

=cut

package Bio::Tools::Run::Genewise;
use vars qw($AUTOLOAD @ISA $PROGRAM $PROGRAMDIR $PROGRAMNAME
            $TMPDIR $TMPOUTFILE @GENEWISE_SWITCHES @GENEWISE_PARAMS
            @OTHER_SWITCHES %OK_FIELD);
use Bio::SeqIO;
use Bio::SeqFeature::Generic;
use Bio::SeqFeature::Gene::Exon; 
use Bio::Root::Root;
use Bio::Tools::Run::WrapperBase;
use Bio::SeqFeature::FeaturePair; 
use Bio::SeqFeature::Gene::Transcript;
use Bio::SeqFeature::Gene::GeneStructure;

@ISA = qw(Bio::Root::Root Bio::Tools::Run::WrapperBase);

# Two ways to run the program .....
# 1. define an environmental variable WISEDIR
# export WISEDIR =/usr/local/share/wise2.2.0
# where the wise2.2.20 package is installed
#
# 2. include a definition of an environmental variable WISEDIR in
# every script that will use DBA.pm
# $ENV{WISEDIR} = '/usr/local/share/wise2.2.20';

BEGIN {
    $PROGRAMNAME='genewise';
    if (defined $ENV{WISEDIR}) {
        $PROGRAMDIR = $ENV{WISEDIR} || '';
        $PROGRAM = Bio::Root::IO->catfile($PROGRAMDIR."/src/bin/",
                                          $PROGRAMNAME.($^O =~ /mswin/i ?'.exe':''));
    }
    else {
        $PROGRAM = $PROGRAMNAME;
    }
    @GENEWISE_PARAMS = qw( DYMEM CODON GENE CFREQ SPLICE SUBS INDEL INTRON NULL KBYTE ALG BLOCK DIVIDE GENER );

    @GENEWISE_SWITCHES = qw(HELP SILENT QUIET ERROROFFSTD);

    # Authorize attribute fields
    foreach my $attr ( @GENEWISE_PARAMS, @GENEWISE_SWITCHES,
                       @OTHER_SWITCHES) { $OK_FIELD{$attr}++; }
}


sub new {
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);
  # to facilitiate tempfile cleanup
  $self->io->_initialize_io();

  my ($attr, $value);
  ($TMPDIR) = $self->io->tempdir(CLEANUP=>1);
  while (@args) {
    $attr =   shift @args;
    $value =  shift @args;
    next if( $attr =~ /^-/ ); # don't want named parameters
    if ($attr =~/'PROGRAM'/i) {
      $self->executable($value);
      next;
    }
    $self->$attr($value);
  }
  return $self;
}


sub AUTOLOAD {
    my $self = shift;
    my $attr = $AUTOLOAD;
    $attr =~ s/.*:://;
    $attr = uc $attr;
    $self->throw("Unallowed parameter: $attr !") unless $OK_FIELD{$attr};
    $self->{$attr} = shift if @_;
    return $self->{$attr};
}

=head2 executable

 Title   : executable
 Usage   : my $exe = $factory->executable();
 Function: Finds the full path to the 'genewise' executable
 Returns : string representing the full path to the exe
 Args    : [optional] name of executable to set path to
           [optional] boolean flag whether or not warn when exe is not found

=cut

sub executable{
   my ($self, $exe,$warn) = @_;

   if( defined $exe ) {
     $self->{'_pathtoexe'} = $exe;
   }

   unless( defined $self->{'_pathtoexe'} ) {
       if( $PROGRAM && -e $PROGRAM && -x $PROGRAM ) {
           $self->{'_pathtoexe'} = $PROGRAM;
       } else {
           my $exe;
           if( ( $exe = $self->io->exists_exe($PROGRAMNAME) ) &&
               -x $exe ) {
               $self->{'_pathtoexe'} = $exe;
           } else {
               $self->warn("Cannot find executable for $PROGRAMNAME") if $warn;
               $self->{'_pathtoexe'} = undef;
           }
       }
   }
   $self->{'_pathtoexe'};
}

=head2  version

 Title   : version
 Usage   : exit if $prog->version() < 1.8
 Function: Determine the version number of the program
 Example :
 Returns : float or undef
 Args    : none

=cut

sub version {
    my ($self) = @_;

    return undef unless $self->executable;
    my $string = `genewise -- ` ;
    $string =~ /\(([\d.]+)\)/;
    return $1 || undef;

}


=head2 predict_genes

 Title   : predict_genes
 Usage   : 2 sequence objects
           $genes = $factory->predict_genes($seq1, $seq2);
 Function: Predict genes
 Returns : A Bio::Seqfeature::Gene:GeneStructure object
 Args    : Name of a file containing a set of 2 fasta sequences in the order of
           peptide and genomic sequences
           or else 2  Bio::Seq objects.

 Throws an exception if argument is not either a string (eg a
 filename) or 2 Bio::Seq objects.  If
 arguments are strings, throws exception if file corresponding to string
 name can not be found.

=cut

sub predict_genes {

    my ($self, $seq1, $seq2)=@_;
    my ($attr, $value, $switch);

# Create input file pointer
    my ($infile1,$infile2)= $self->_setinput($seq1, $seq2);
    if (!($infile1 && $infile2)) {$self->throw("Bad input data (sequences need an id ) ");}


# run genewise
    my $feats = $self->_run($infile1,$infile2);
    return $feats;
}


=head2  _run

 Title   :  _run
 Usage   :  Internal function, not to be called directly
 Function:   makes actual system call to a genewise program
 Example :
 Returns : nothing; genewise  output is written to a
           temporary file $TMPOUTFILE
 Args    : Name of a files containing 2 sequences in the order of peptide and genomic

=cut

sub _run {
    my ($self,$infile1,$infile2) = @_;
    my $instring;
    $self->debug( "Program ".$self->executable."\n");
    #my $outfile = $self->outfile() || $TMPOUTFILE ;
    my ($tfh1,$outfile) = $self->io->tempfile(-dir=>$TMPDIR);
    my $paramstring = $self->_setparams;
    my $commandstring = $self->executable." $paramstring $infile1 $infile2 > $outfile";
    $self->debug( "genewise command = $commandstring");
    my $status = system($commandstring);
    $self->throw( "Genewise call ($commandstring) crashed: $? \n") unless $status==0;

    #parse the outpur and return a Bio::SeqFeature::Gene::GeneStructure object
    my $genes   = $self->_parse_results($outfile);

    return $genes;
}

=head2  _parse_results

 Title   :  _parse_results
 Usage   :  Internal function, not to be called directly
 Function:  Parses genewise output
 Example :
 Returns : a Bio::SeqFeature::Gene::GeneStructure object
 Args    : the name of the output file

=cut

sub _parse_results {
    my ($self,$outfile) = @_;
    $outfile||$self->throw("No outfile specified");
    my ($self) = @_;

    print STDERR "Parsing the file\n";

    my $filehandle;
    if (ref ($outfile) !~ /GLOB/)
    {
        open (GENEWISE, "<".$outfile)
            or $self->throw ("Couldn't open file ".$outfile.": $!\n");
        $filehandle = \*GENEWISE;
    }
    else
    {
        $filehandle = $outfile;
    }
    my $genes = new Bio::SeqFeature::Gene::GeneStructure ;
    my $transcript = new Bio::SeqFeature::Gene::Transcript ;
    my $curr_exon;
    my $score;
    #The big parsing loop - parses exons and predicted peptides
    $/ = "\n//\n";
    while (<$filehandle>) {
        chomp;
        my @f = split;
        if (scalar(@f)>50) { #super tedious way of fetching the score from the
          $score = $f[81];
        }  
        if (scalar(@f)<50) { #this condition ignores the "irrelevant"(in ensembl context) part of the results 
          my $seqname = $f[0]." ".$f[1];
          my $start = $f[3];
          my $end = $f[4];
          my $strand = 1;
          if ( $f[3] > $f[4] ) {
              $strand = -1;
              $start = $f[4]; 
              $end = $f[3];
          }
          $curr_exon = new Bio::SeqFeature::Gene::Exon (-seqname=>$seqname, -start=>$start, -end=>$end, -strand=>$strand); 
	        $curr_exon->add_tag_value( $f[8] => $f[9] );
           
          my $gstart = $f[11];
          my $gend = $f[12];
          my $gstrand = 1;
          if ($gstart > $gend){
              $gstart = $f[12];
              $gend = $f[11];
              $gstrand = -1;
          }
          if ( $gstrand != $strand ) {
              $self->throw("incompatible strands between exon and supporting feature - cannot add suppfeat\n");
          }

          my $pstart = $f[13];
          my $pend = $f[14];
          my $pstrand = 1;          
          if($pstart > $pend){
              $self->warn("Protein start greater than end! Skipping this suppfeat\n");
          }

      	  my $pf = new Bio::SeqFeature::Generic( -start   => $pstart,
						  -end     => $pend,
						  -seqname => 'protein',
					    -score   => $score,
              -strand  => $pstrand,
					    -source_tag => 'genewise',
              -primary_tag => 'supporting_protein_feature',
              ); 
					$pf->source_tag('genewise');
          $pf->primary_tag('supporting_protein_feature');
      	  my $gf  = new Bio::SeqFeature::Generic( -start   => $gstart,
						  -end     => $gend,
						  -seqname => 'genomic',
              -score   => $score,
						  -strand  => $gstrand,
						  -source_tag => 'genewise',
              -primary_tag => 'supporting_genomic_feature',
              );
					$gf->source_tag('genewise');
          $gf->primary_tag('supporting_genomic_feature');
	        
          $curr_exon->add_tag_value( 'supporting_protein_feature' => $pf );
	        $curr_exon->add_tag_value( 'supporting_genomic_feature' => $gf );

          
          #my $fp = new Bio::SeqFeature::FeaturePair( -feature1 => $pf,
					#	  -feature2 => $gf);
	        #$curr_exon->add_sub_SeqFeature($fp);
          
         # for listing out elements of the array
         # for ( my $i=0; $i<scalar(@f); $i++) { 
         #     print "$i "."$f[$i]\n";
         # } 
        }
    }
    $transcript->add_exon($curr_exon);
    $genes->add_transcript($transcript);
    return $genes
}

sub _setinput {
  my ($self, $seq1, $seq2) = @_;
  my ($tfh1,$tfh2,$outfile1,$outfile2);

    if(!($seq1->isa("Bio::PrimarySeqI") && $seq2->isa("Bio::PrimarySeqI")))
      { $self->throw("One or more of the sequences are nor Bio::PrimarySeqI objects\n"); }
    my $tempdir = $self->io->tempdir(CLEANUP=>1);
    ($tfh1,$outfile1) = $self->io->tempfile(-dir=>$tempdir);
    ($tfh2,$outfile2) = $self->io->tempfile(-dir=>$tempdir);

    my $out1 = Bio::SeqIO->new(-file=> ">$outfile1" , '-format' => 'Fasta');
    my $out2 = Bio::SeqIO->new(-file=> ">$outfile2", '-format' => 'Fasta');

    $out1->write_seq($seq1);
    $out2->write_seq($seq2);
    $self->_query_pep_seq($seq1);
    $self->_subject_dna_seq($seq2);
    return $outfile1,$outfile2;

}
=head2 _setparams

 Title   :  _setparams
 Usage   :  Internal function, not to be called directly
 Function:  creates a string of params to be used in the command string
 Example :
 Returns :  string of params
 Args    :  

=cut
      
sub _setparams {
    my ($self) = @_;
    my $param_string;
    foreach my $attr(@GENEWISE_PARAMS){
        my $value = $self->$attr();
        next unless (defined $value);
        my $attr_key = ' -'.(lc $attr);
        $param_string .=$attr_key.' '.$value;
    }
    foreach my $attr(@GENEWISE_SWITCHES){
        my $value = $self->$attr();
        next unless (defined $value);
        my $attr_key = ' -'.(lc $attr);
        $param_string .=$attr_key;
    }

    $param_string = $param_string." -genesf"; #specify the output option
    return $param_string;
}

=head2 _query_pep_seq

 Title   :  _query_pep_seq
 Usage   :  Internal function, not to be called directly
 Function:  get/set for the query sequence
 Example :
 Returns :  
 Args    :

=cut

sub _query_pep_seq {
  my ($self,$seq) = @_;
  if(defined $seq){
    $self->{'_query_pep_seq'} = $seq;
  }
  return $self->{'_query_pep_seq'};
}

=head2 _subject_dna_seq

 Title   :  _subject_dna_seq
 Usage   :  Internal function, not to be called directly
 Function:  get/set for the subject sequence
 Example :
 Returns :

 Args    :

=cut

sub _subject_dna_seq {
  my ($self,$seq) = @_;
  if(defined $seq){
    $self->{'_subject_dna_seq'} = $seq;
  }
  return $self->{'_subject_dna_seq'};
}
1; 

