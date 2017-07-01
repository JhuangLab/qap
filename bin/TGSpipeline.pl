#!/usr/bin/env perl

#################################################################################
##                                                                             ##
##                       Quasispecies Analysis Package                         ##
##                                                                             ##
#################################################################################
##                                                                             ##
##  A software suite designed for virus quasispecies analysis                  ##
##  See our website: <http://bioinfo.rjh.com.cn/labs/jhuang/tools/gap/>        ##
##                                                                             ##
##  Version 1.0                                                                ##
##                                                                             ##
##  Copyright (C) 2017 by Mingjie Wang, All rights reserved.                   ##
##  Contact:  huzai@sjtu.edu.cn                                                ##
##  Organization: Research Laboratory of Clinical Virology, Rui-jin Hospital,  ##
##  Shanghai Jiao Tong University, School of Medicine                          ##
##                                                                             ##
##  This file is a subprogram of GAP suite.                                    ##
##                                                                             ##
##  QAP is a free software; you can redistribute it and/or                     ##
##  modify it under the terms of the GNU General Public License                ##
##  as published by the Free Software Foundation; either version               ##
##  3 of the License, or (at your option) any later version.                   ##
##                                                                             ##
##  QAP is distributed in the hope that it will be useful,                     ##
##  but WITHOUT ANY WARRANTY; without even the implied warranty of             ##
##  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              ##
##  GNU General Public License for more details.                               ##
##                                                                             ##
##  You should have received a copy of the GNU General Public                  ##
##  License along with ViralFusionSeq; if not, see                             ##
##  <http://www.gnu.org/licenses/>.                                            ##
##                                                                             ##
#################################################################################


use diagnostics;
use strict;
use warnings;
use FindBin qw/$RealBin/;
use File::Spec;
use Getopt::Long;
use Pod::Usage;
use lib "$FindBin::Bin/../lib";
use Cwd qw/getcwd abs_path/;
use File::Basename;
use File::Copy;

####Use modules in this program####
use General;
use Mapper;

####---------------------------####
####The program begins here
####---------------------------####

##Show welcome
print "You are now running subprogram: ";
printcol ("TGSpipeline","green");
print "\n";

## check threads available or not
$| = 1;
InfoPlain("Checking threading status");
sleep(1);
my $threads_usable = eval 'use threads; 1';
if ($threads_usable) {
	use threads;
	use threads::shared;
	InfoPlain("Perl threading enabled");
} else {
	Info("No threading is possible. Please install perl module: threads or recompile perl with option -Dusethreads","red");
}

##get workding directory
my $wk_dir = getcwd;
my $mainBin;
if ($RealBin =~ /(.*)\/bin/){
	$mainBin = $1;
}

####define command line arguments
my $help;
my $inputfile;
my $outputDir;
my $threads;
my $ref;

my $DateNow = `date +"%Y%m%d_%Hh%Mm%Ss"`;
chomp $DateNow;

GetOptions(
'i|inputFq|=s'       => \$inputfile,
'o|outputDir|=s'     => \$outputDir,
'h|help|'            => \$help,
't|threads|=s'       => \$threads,
'r|refSeq|=s'        => \$ref
);


##check command line arguments
if (defined $help){
	pod2usage(-verbose=>2,-exitval=>1);
}

if (defined $outputDir){
	$outputDir = abs_path($outputDir) . "/";
	if (not -e $outputDir){
 		InfoWarn("The output directory $outputDir does NOT exist.",'yellow');
 		InfoWarn("Will mkdir $outputDir and use it as the output directory.",'yellow');
		#pod2usage(-verbose=>0,-exitval=>1);
		#exit;
		my $cmd = "mkdir -p $outputDir";
		system($cmd);
	}
}else{
	$outputDir = File::Spec -> catfile($wk_dir,"qap_Results_for_TGSpipeline_$DateNow");
	InfoWarn("The output directory is not provided!",'yellow');
	InfoWarn("Will mkdir \"$outputDir\" and use it as the output directory.",'yellow');
	
	if (!-e "$outputDir"){
		my $cmd = "mkdir -p $outputDir";
		system($cmd);
	}else{
		InfoError("Mkdir Failed! $outputDir already exists!","red");
		InfoError("Please specify another output directory using option -o/--outputDir\n");
		pod2usage(-verbose=>2,-exitval=>1);
		exit;
	}

}

if (defined $threads){
	my $check_threads_positive = &CheckPositiveInt($threads);
	my $threads_max = `grep 'processor' /proc/cpuinfo | sort -u | wc -l`;
	chomp $threads_max;

	if ($check_threads_positive && $threads <= $threads_max){
		#threads provided by user is ok, doing nothing
	}else{
		InfoError("Threads number wrong!",'red');
		InfoError("Please provide a threads number between 0 - $threads_max that this server could support.");
		
		pod2usage(-verbose=>2,-exitval=>1);
		exit;
	}
}else{
	$threads = 1;#if -t not provided, default is NOT use theads;
}

my @fqfiles;
if (defined $inputfile){
	my @tmp = split ",",$inputfile;
	for my $tmp (@tmp){
		$tmp =~ s/\s//g;
		if (not -e $tmp){
			InfoError("Input fastq file $tmp does NOT exist!",'red');
			exit;
		}else{
			my $pathtmp = abs_path($tmp);
			push @fqfiles,$pathtmp;
		}
	}
}else{
	InfoError("Input fastq files MUST be provided!",'red');
	pod2usage(-verbose=>2,-exitval=>1);
	exit;
}

my @ref;
my $isMultiRef = 0;
if (defined $ref){
	if ($ref !~ /\,/){
		if (not -e $ref){
			InfoError("Input reference file $ref does NOT exist!",'red');
			exit;
		}else{
			if(isGzipped($ref)){
				InfoError("The reference file you provided is gzipped. Please uncompress it using \"gunzip $ref\" and re-run the program. ");
				exit;
			}
			$ref = abs_path($ref);
			push @ref,$ref;
		}
	}else{
		my @tmp = split ',',$ref;
		
		$isMultiRef = 1;
		
		#check the number of files provided are equal or not 
		my $num1 = scalar(@fqfiles);
		my $num2 = scalar(@tmp);
		
		if ($num1 == $num2){
			#nothing
		}else{
			InfoError("There are $num1 fastq files, and $num2 reference files provided! Please check again.", "red");
			pod2usage(-verbose=>1,-exitval=>1);
			exit;
		}
		
		#check ref file status
		for my $r (@tmp){
			if (not -e $r){
				InfoError("Input reference file $r does NOT exist!",'red');
				exit;
			}else{
				if(isGzipped($r)){
					InfoError("The reference file you provided is gzipped. Please uncompress it using \"gunzip $r\" and re-run the program. ");
					exit;
				}
				my $rpath = abs_path($r);
				push @ref,$rpath;
			}
		}
	}
	
}else{
	InfoError("Input reference file MUST be provided!",'red');
	pod2usage(-verbose=>1,-exitval=>1);
	exit;
}

##handle line break
my $tmpdir = File::Spec -> catfile($outputDir,'tmp');
makedir($tmpdir);
my $fqdir = File::Spec -> catfile($tmpdir, 'fastq');
makedir($fqdir);
my $refdir = File::Spec -> catfile($tmpdir, 'ref');
makedir($refdir);

my @newfqfiles;
for my $fq (@fqfiles){
	copy($fq,$fqdir);
	my $newfq = File::Spec -> catfile($fqdir,basename($fq));
	windows2linux($newfq);
	push @newfqfiles,$newfq;
}

my @newref0;
for my $r (@ref){
	copy($r,$refdir);
	my $newref = File::Spec -> catfile($refdir, removeFastaSuffix(basename($r)) . ".fasta");
	windows2linux($newref);
	
	#formatFastaToTwoLineMode
	my $newref2 = $newref =~ s/\.fasta$/.2line.fasta/r;
	formatFastaToTwoLineMode($newref,$newref2);
	push @newref0,$newref2;
}
my @newref;
if(scalar(@ref) == 1){
	map {push @newref,$newref0[0];} @newfqfiles;
}else{
	map {push @newref,$_;} @newref0;
}

##check blast
my $DEBUG_MODE = 1;
my $makeblastdb_excu = File::Spec -> catfile($mainBin,'3rdPartyTools','blast','makeblastdb');
if(CheckProgram($makeblastdb_excu, __FILE__, __LINE__, $DEBUG_MODE)){
	#keep running
}else{
	InfoError("The program $makeblastdb_excu does NOT exist. Exiting...");
	exit;
}
my $blastn_excu = File::Spec -> catfile($mainBin,'3rdPartyTools','blast','blastn');
if(CheckProgram($blastn_excu, __FILE__, __LINE__, $DEBUG_MODE)){
	#keep running
}else{
	InfoError("The program $blastn_excu does NOT exist. Exiting...");
	exit;
}

##check fq2fa
my $fq2fa_excu = File::Spec -> catfile($mainBin,'3rdPartyTools','fastx_toolkit','fq2fa');
if(CheckProgram($fq2fa_excu, __FILE__, __LINE__, $DEBUG_MODE)){
	#keep running
}else{
	InfoError("The program $fq2fa_excu does NOT exist. Exiting...");
	exit;
}


##fastq 2 fasta
my $fastadir = File::Spec -> catfile($tmpdir,'fasta');
makedir($fastadir);

my @fastafiles;
for my $fq (@newfqfiles){
	if(isGzipped($fq)){
		system("gunzip $fq");
		$fq =~ s/.gz$//;
	}

	my $fasta = removeFastqSuffix($fq) . ".fasta";
	my $cmd = "$fq2fa_excu -in $fq -out $fasta";
	runcmd($cmd);
		
	push @fastafiles,$fasta;
}


##run blast first
my $blastdir = File::Spec -> catfile($tmpdir, 'blast');
makedir($blastdir);

my $numberOfSamples = scalar(@fastafiles);
my $threadsForEachSample = int($threads / $numberOfSamples);
$threadsForEachSample = 1 if $threadsForEachSample <= 1;

my @makeblastdb;
my @blastn;
my @blastout1;
my @blastout2;
my @fmt6;
my @nofmt6;
my @eachthreads;
for my $f (@fastafiles){
	push @makeblastdb,$makeblastdb_excu;
	push @blastn,$blastn_excu;
	push @fmt6,'1';
	push @nofmt6,'0';
	push @eachthreads,$threadsForEachSample;
	my $out1 = File::Spec -> catfile($blastdir, removeFastaSuffix(basename($f)) . ".1.BlastOut");
	push @blastout1,$out1;
	my $out2 = File::Spec -> catfile($blastdir, removeFastaSuffix(basename($f)) . ".2.BlastOut");
	push @blastout2,$out2;
}
runMultipleThreadsWith7Args(\&blastPipeline, \@makeblastdb, \@blastn, \@newref, \@fastafiles, \@blastout1, \@fmt6, \@eachthreads, $threads);
runMultipleThreadsWith7Args(\&blastPipeline, \@makeblastdb, \@blastn, \@newref, \@fastafiles, \@blastout2, \@nofmt6, \@eachthreads, $threads);

##handle blast out
my @outputfile;
for my $f (@fastafiles){
	my $outfile = File::Spec -> catfile($outputDir, removeFastaSuffix(basename($f)) . ".rebuild.fasta");
	push @outputfile,$outfile;
}

runMultipleThreadsWith5Args(\&qsrFromBlastout, \@newref, \@fastafiles, \@blastout1, \@blastout2, \@outputfile, $threads);


##sub programs starts here
sub qsrFromBlastout {
	my $refseqFile = shift;
	my $seqFile = shift;
	my $blastfile1 = shift;
	my $blastfile2 = shift;
	my $outputfile = shift;
	
	Info("Rebuilding quasispecies for $seqFile.");
	sleep(1);
	##modify query file
	my $delfile = $blastfile2 . ".Del";
	my $num = 10; #line to delete
	my $max = `sed -n \'\$\=\' $blastfile2`; #total line number of the file
	chomp $max;
	my $sLine = $max - $num + 1; #the start line to be deleted
	
	#delete first 10 lines
	my $cmd = "sed \'$sLine,$max d' $blastfile2 > $delfile";
	system($cmd);
	
	open T,$delfile or die "Can not open $delfile:$!";
	map {my $dump = <T>} (1..14);
	
	$/ = 'Query=';
	
	my $tmpfile1 = $delfile . '.Tmp';
	open RES, ">$tmpfile1" or die "Can NOT output to $tmpfile1:$!";
	
	while(my $line = <T>){
		if ($line =~ /Score \=/){
			#nothing
		}else{
			next;
		}
		
		my @arr = split "Score =",$line;
	
		for my $seq (@arr){
			if ($seq =~ /Identities/){
				#nothing
			}else{
				next;
			}
			my @subline = split "\n",$seq;
			my $query;
			my $subject;
			my $hyphen;
			
			for my $subsubline (@subline){
				#print "--$subsubline--\n";
				if ($subsubline =~ /Query  /){
					$subsubline = substr $subsubline,13,60;
					$subsubline =~ s/  \d+$//;
					$query .= $subsubline;
				}elsif($subsubline =~ /\|\|/){
					$subsubline = substr $subsubline,13,60;
					$hyphen .= $subsubline;
				}elsif($subsubline =~ /Sbjct  /){
					$subsubline = substr $subsubline,13,60;
					$subsubline =~ s/  \d+$//;
					$subject .= $subsubline;
				}else{
					next;
				}
			}
			print RES "$query\n";
			print RES "$hyphen\n";
			print RES "$subject\n";
			
		}
	}
	close T;
	close RES;
	
	$/ = "\n";
	
	open T,$tmpfile1 or die "Can NOT open $tmpfile1:$!";
	
	my $modifyseqfile = $blastfile2 . ".modifySeq.txt";
	open RES,">$modifyseqfile" or die "Can NOT output to $modifyseqfile:$!";
	
	my @seqMod;
	while (my $line1 = <T>) {
		chomp $line1;
		chomp (my $line2 = <T>);
		chomp (my $line3 = <T>);
		
		my @query = split '',$line1;
		my @subj = split '',$line3;
		my @queryMod;
		for my $i (1..scalar(@query)){
			my $letterQuery = $query[$i - 1];
			my $letterSubj = $subj[$i - 1];
			
			if ($letterQuery ne '-' && $letterSubj ne '-'){
				push @queryMod,$letterQuery;
			}elsif($letterQuery eq '-' && $letterSubj ne '-'){
				push @queryMod,$letterSubj;
			}elsif($letterQuery ne '-' && $letterSubj eq '-'){
				#doing nothing;	
			}else{
				die "error";
			}
		}
		my $queryMod = join '',@queryMod;
		print RES "$queryMod\n";
		push @seqMod,$queryMod;
	}
	close T;
	close RES;
	
	##rebuild alignment file
	open T,$refseqFile or die "Can NOT open $refseqFile:$!";
	my $refseq;
	while (my $line1 = <T>) {
		chomp $line1;
		chomp (my $line2 = <T>);
		$refseq = $line2;
	}
	close T;
	
	open T,$seqFile or die "Can NOT open $seqFile:$!";
	my %seq;
	while (my $line1 = <T>) {
		chomp $line1;
		chomp (my $line2 = <T>);
		
		my $seqname = $line1 =~ s/^>//r;
		$seq{$seqname} = $line2;
		
	}
	close T;
	
	open T,$blastfile1 or die "Can NOT open $blastfile1:$!";
	
	my %newseq;
	for my $id (keys %seq){
		$newseq{$id} = $refseq;
		#print "$id\n";
	}
	
	my $n = 0;
	while (<T>) {
		chomp;
		my @tmp = split "\t",$_;
		my ($seqName,$queryStart,$queryEnd,$targetStart,$targetEnd) = @tmp[0,6,7,8,9];
		
		if ($targetStart < $targetEnd){
			my $sublen = $targetEnd - $targetStart + 1;
			#print ">>$seqName<<\n";
			#print "$newseq{$seqName}\n";
			$newseq{$seqName} =~ s/ //g;
			if (substr $newseq{$seqName},$targetStart - 1, $sublen, $seqMod[$n]){
				#nothing;
			}
			#print "$seqName:substr $newseq{$seqName},$targetStart - 1, $sublen, $seqMod[$n]\n";

		}elsif($targetStart > $targetEnd){
			my $sublen = $targetStart - $targetEnd + 1;
			my $subseq = &rc($seqMod[$n]);
			#print "$seqName\n";
			#print "$newseq{$seqName}\n";
			$newseq{$seqName} =~ s/ //g;
			if (substr $newseq{$seqName},$targetEnd - 1, $sublen, $subseq){
				#nothing;
			}
				#print "$seqName:substr $newseq{$seqName},$targetEnd - 1, $sublen, $subseq\n";
			
		}else{
			Info("Error! Start position equals End position at LINE $n in $blastfile1");
		}
		
		$n++;
	}
	close T;
	
	open RES,">$outputfile" or die "Can not output to $outputfile:$!";
	for my $id (keys %newseq){
		$newseq{$id} =~ s/ //g;
		print RES ">$id\n$newseq{$id}\n";
	}
	close RES;
}

##run success
Info("Program completed!",'green');


####---------------------------####
####The program ends here
####---------------------------####


=pod 

=head1 NAME

qap -- Quasispecies analysis package

=head1 SYNOPSIS


       ______       ______       ______
      / ___  |     / ____ \     |  ___ \
     / /   | |    / |    | |    | |   \ \
    | |    | |    | |    |_|    | |    | |
     \ \___| |    \ |____\ \    | |___/ /
      \____  |     \_____/\_\   | |____/
           | |                  | |
           | |                  | |
           | |                  | |
           |_|                  |_|         v1.0
           



gap TGSpipeline [options]

Use --help to see more information.

gap is still in development. If you have encounted any problem in usage, please feel no hesitation to cotact us.

=head1 DESCRIPTION

This script implements a function to pre-process raw read files from PacBio third generation sequencing data. The script has B<several> mandatory options that MUST appear last. 

=head1 OPTIONS

=over 5

=item --inputFq,-i F<FILE> [Required]

Path to input BAM/SAM file which is required. You can also provide multiple files and seperate them by comma, e.g. -i test1.fastq,test2.fastq

=item --refSeq,-r F<File> [Required]

Path to the reference fasta file. If all the sample use the same reference file, only one reference file should be provided. If the samples used different references, please provide all the reference files for each sequence data, and separated them by comma. e.g. -r hbv.fasta or -r hbv1.fasta,hbv2.fasta,hbv3.fasta. 

=item --outputDir,-o F<FILE> [Optional]

Path of the directory to storage result files. If NOT provided, the program will generate a folder automatically.

=item --threads,-t F<INTEGER> [Optional]

Number of threads this program will use when computing. A positive integer should be provided. The default value is 1.

=item --help,-h

Display this detailed help information.

=back

=head1 EXAMPLE

=over 5

gap TGSpipeline -i test1.fastq,test2.fastq -r hbv1.fasta,hbv2.fasta,hbv3.fasta -t 5 -o ./tgs

=back

=head1 AUTHOR

Mingjie Dr.Wang I<huzai@sjtu.edu.cn>

=head1 COPYRIGHT

Copyright (C) 2017, Mingjie Wang. All rights reserved.
