#!/usr/bin/env perl

#################################################################################
##                                                                             ##
##                       Quasispecies Analysis Package                         ##
##                                                                             ##
#################################################################################
##                                                                             ##
##  A software suite designed for virus quasispecies analysis                  ##
##  See our website: <http://bioinfo.rjh.com.cn/labs/jhuang/tools/qap/>        ##
##                                                                             ##
##  Version 1.0                                                                ##
##                                                                             ##
##  Copyright (C) 2017 by Mingjie Wang, All rights reserved.                   ##
##  Contact:  huzai@sjtu.edu.cn                                                ##
##  Organization: Research Laboratory of Clinical Virology, Rui-jin Hospital,  ##
##  Shanghai Jiao Tong University, School of Medicine                          ##
##                                                                             ##
##  This file is a subprogram of QAP suite.                                    ##
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
##  License along with QAP; if not, see                                        ##
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


####Use modules in this program####
use General;

####---------------------------####
####The program begins here
####---------------------------####

##Show welcome
print "You are now running subprogram: ";
printcol ("PickClusterOTU","green");
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
my $inputDir;
my $outputDir;
my $threads;
my $suffix;
my $ratio;

my $DateNow = `date +"%Y%m%d_%Hh%Mm%Ss"`;
chomp $DateNow;

GetOptions(
'i|inputDir|=s'      => \$inputDir,
'o|outputDir|=s'     => \$outputDir,
'h|help|'            => \$help,
't|threads|=s'       => \$threads,
'r|ratio|=s'         => \$ratio,
's|suffix|=s'        => \$suffix
);


##check command line arguments
if (defined $help){
	pod2usage(-verbose=>2,-exitval=>1);
}

if (defined $outputDir){
	$outputDir =~ s/\/$//;
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
	$outputDir = File::Spec -> catfile($wk_dir,"qap_Results_for_PickClusterOTU_$DateNow");
	InfoWarn("The output directory is not provided!",'yellow');
	InfoWarn("Will mkdir \"$outputDir\" and use it as the output directory.",'yellow');
	
	if (!-e "$outputDir"){
		my $cmd = "mkdir -p $outputDir";
		system($cmd);
	}else{
		InfoError("Mkdir Failed! $outputDir already exists!","red");
		InfoError("Please specify another output directory using option -o/--outputDir\n");
		pod2usage(-verbose=>0,-exitval=>1);
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
		
		pod2usage(-verbose=>0,-exitval=>1);
		exit;
	}
}else{
	$threads = 1;#if -t not provided, default is NOT use theads;
}

if(defined $inputDir){
	$inputDir = abs_path($inputDir) . "/";
	if (not -e $inputDir){
		InfoError("Input directory $inputDir does NOT exist! Please check again.");
		exit;
	}
}else{
	InfoError("Input directory MUST be specified with -i/--inputDir\n");
	pod2usage(-verbose=>0,-exitval=>1);
	exit;
}

my $tmpDir = File::Spec -> catfile($outputDir,'tmp');
makedir($tmpDir);

if(defined $ratio){
	if(CheckDouble($ratio) and $ratio >= 0 and $ratio <= 1){
		#nothing
	}else{
		InfoError("--ratio/-r should be defined with a decimal number lager than 0 and less than 1.");
		pod2usage(-verbose=>0,-exitval=>1);
		exit;
	}
}else{
	$ratio = 0.2;
}

my $numberOfFiles = 0;
my @inputfiles;
if(defined $suffix){
	@inputfiles = glob ("${inputDir}/*.${suffix}");
	
	$numberOfFiles = scalar(@inputfiles);
	
	if ($numberOfFiles == 0){
		InfoError("There are NOT any files in $inputDir with suffix \'.${suffix}\'. Please check again.");
		exit;
	}
	
	Info("Find $numberOfFiles files.");
	my $i = 1;
	my @seqLen;
	for my $f (@inputfiles){
		my $len = checkSeqLen($f, $tmpDir);
		push @seqLen,$len;
		printf "[%02d] $f -- $len bp\n",$i;
		$i++;
	}
	
	##check seq length all equal
	if(checkMultipleEqualNums(\@seqLen)){
		Info("Sequence length all equal to $seqLen[0] --- PASS");
	}else{
		InfoError("Sequence length not equal. Please check. Exiting...");
		exit(0);
	}
	
}else{
	InfoWarn("The suffix is not provided. The program will try to read in every file in $inputDir");
	
	@inputfiles = glob ("${inputDir}/*.*");
	
	$numberOfFiles = scalar(@inputfiles);
	
	if ($numberOfFiles == 0){
		InfoError("There are NOT any files in $inputDir with suffix \'.${suffix}\'. Please check again.");
		exit;
	}
	
	Info("Find $numberOfFiles files.");
	my $i = 1;
	my @seqLen;
	for my $f (@inputfiles){
		my $len = checkSeqLen($f, $tmpDir);
		push @seqLen,$len;
		printf "[%02d] $f -- $len bp\n",$i;
		$i++;
	}
	
	##check seq length all equal
	if(checkMultipleEqualNums(\@seqLen)){
		Info("Sequence length all equal to $seqLen[0] --- PASS");
	}else{
		InfoError("Sequence length not equal. Please check. Exiting...");
		exit(0);
	}
	
}

sleep(1);


##start to calculate
#program
my $DEBUG_MODE = 1;
my $swarm_excu = File::Spec -> catfile($RealBin,'3rdPartyTools','cluster','swarm','swarm');
if(CheckProgram($swarm_excu, __FILE__, __LINE__, $DEBUG_MODE)){
	#keep running
}else{
	InfoError("The program $swarm_excu does NOT exist. Exiting...");
	exit;
}

#convert to 2line mode
Info("Convert fasta files and calculate OTU sequences.");
my @inputfiles2line;
my $i = 1;

my $swarmInput = File::Spec -> catfile($tmpDir,"MergeNoDel.fasta");
open NODEL,">$swarmInput" or die "Can NOT output to $swarmInput:$!"; 

my $otuDir = File::Spec -> catfile($outputDir, "OTU");
makedir($otuDir);

my @f_withoutDel;
for my $f (@inputfiles){
	#windows2linux($f);
	
	my $f2line = File::Spec -> catfile($tmpDir,removeFastaSuffix(basename($f)) . ".2line.fasta");
	formatFastaToTwoLineMode($f,$f2line);
	my $id = removeFastaSuffix(basename($f));
	my $fname = basename($f);
	
	# deal with sequence files with deletions 	
	open T,$f2line or die "Can NOT open file $f:$!";
	my $f_withDel = File::Spec -> catfile($tmpDir,$id . ".withDel.fasta");
	open DEL,">$f_withDel" or die "Can NOT output to $f_withDel:$!";	
	my $f_withoutDel = File::Spec -> catfile($tmpDir, $id. "withoutDel.fasta");
	open NODELEACH,">$f_withoutDel" or die "Can NOT output to $f_withoutDel:$!";
	push @f_withoutDel,$f_withoutDel;
	
	my $seqNum;
	my $seqWithoutDelNum;
	while(my $line1 = <T>){
		chomp $line1;
		chomp (my $line2 = <T>);
		
		if($line2 =~ /-/){
			print DEL "$line1\n$line2\n";
		}else{
			$seqWithoutDelNum++;
			print NODEL ">[${id}][-][OTU${seqWithoutDelNum}]\n$line2\n";
			print NODELEACH ">[${id}][-][OTU${seqWithoutDelNum}]\n$line2\n";
		}
		
		$seqNum++;
		#print RINPUT "$line2\t$id\n";
	}
	close DEL;
	close NODELEACH;
	
	sleep 1;
	printf "[%02d] $id: ",$i;
	print "$seqWithoutDelNum / $seqNum sequences without special characters were detected.\n";
	$i++;
}
close(NODEL);

#cluster seq for each sample
for my $f (@f_withoutDel){
	my $id = removeFastaSuffix(basename($f));
	$id =~ s/withoutDel//;
	##run swarm for each sample and generate the otu seq
	Info("Calculating OTU clusters for $id");
	sleep(1);
	my $swarmSeqFile = File::Spec -> catfile($tmpDir, $id . ".swarmOTU.tmp.fasta");
	my $swarmCountFile = File::Spec -> catfile($tmpDir, $id . ".swarmOTUCluster.tmp.txt");
	my $swarmCMD = "$swarm_excu -a 1 -w $swarmSeqFile -o $swarmCountFile $f";
	runcmd($swarmCMD);
	
	my $finalOTUseq = File::Spec -> catfile($otuDir, $id . ".OTU.fasta");
	open OUT,">$finalOTUseq" or die "Can NOT output to $finalOTUseq:$!";
	
	#convert seq cluster to OTU seq
	open T,$swarmSeqFile or die "Can NOT output to $swarmSeqFile:$!";
	my $otuNum;
	while(my $line1 = <T>){
		chomp $line1;
		chomp (my $line2 = <T>);
		
		if($line1 =~ /\[(.*?)\]\[\-\]\[.*?\]_(\d+)/){
			$otuNum++;
			print OUT ">$1-OTU${otuNum};size=$2\n";
			print OUT "$line2\n";
		}
	}
	close OUT;
	close T;
}




#run cluster
Info("Running Swarm for sequence cluster.");
my $clusterOut = File::Spec -> catfile($tmpDir,"SwarmOut.txt");
my $clusterSeq = File::Spec -> catfile($tmpDir,"SwarmOut.seq");

my $cmd = "$swarm_excu -a 1 -t $threads -w $clusterSeq -o $clusterOut $swarmInput";
runcmd($cmd);

#convert cluster out to R input
my @otuseq;
open SEQ,$clusterSeq or die "Can NOT open $clusterSeq:$!";
while(my $line1 = <SEQ>){
	chomp $line1;
	chomp (my $line2 = <SEQ>);
	push @otuseq,$line2;
}
 
my $rinput = File::Spec -> catfile($tmpDir,"RINPUT.txt");
open RINPUT,">$rinput" or die "Can not output to $rinput:$!";

open C,$clusterOut or die "Can NOT open swarm output $clusterOut:$!";
my $otuNum = 0;
while(<C>){
	chomp;
	my @tmp = split " ",$_;
	for my $e (@tmp){
		if($e =~ /\[(.*?)\]\[-\]\[/){
			print RINPUT "$otuseq[$otuNum]\t$1\n";
		}
	}
	$otuNum++;
}
close C;
close RINPUT;

#start to count
my $rscript = File::Spec -> catfile($RealBin,'Rscripts','CalculateClusterOTUTable.R');
if(! existFile($rscript)){
	InfoError("Rscript $rscript is missing. Please check. Exiting...");
	exit(0);
}

#generate OTU table
Info("Generating OTU table");
my $finalOut = File::Spec -> catfile($outputDir,"OTUTable.txt");
$cmd = "Rscript $rscript --inputFile $rinput --outputFile $finalOut --sampleRatio $ratio";
runcmd($cmd);


##run success
print("\n\n");
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
           



qap PickClusterOTU [options]

Use --help to see more information.

qap is still in development. If you have encounted any problem in usage, please feel no hesitation to cotact us.

=head1 DESCRIPTION

This script implements a function to pick OTUs based on amplicon sequence clusters and generate an OTU table. The script has B<several> mandatory options that MUST appear last. 

=head1 OPTIONS

=over 5

=item --inputDir,-i F<FILE> [Required]

Path to directory contaning all the files to be read in.

=item --suffix,-s F<STRING> [Optional]

Suffix of the files to be read in. If suffix is not provided, all the files in input directory will be read in.

=item --outputDir,-o F<FILE> [Optional]

Path of the directory to storage result files. If NOT provided, the program will generate a folder automatically.

=item --ratio,-r F<DOUBLE> [Optional]

Ratio of samples with specific OTUs among all sampels. Default value is 0.2.

=item --threads,-t F<INTEGER> [Optional]

Number of threads this program will use when computing. A positive integer should be provided. The default value is 1.

=item --help,-h

Display this detailed help information.

=back

=head1 EXAMPLE

=over 5

qap PickClusterOTU -i ./seq -s fasta -t 10 -c 2 -o ./result

=back

=head1 AUTHOR

Mingjie Dr.Wang I<huzai@sjtu.edu.cn>

=head1 COPYRIGHT

Copyright (C) 2017, Mingjie Wang. All rights reserved.

