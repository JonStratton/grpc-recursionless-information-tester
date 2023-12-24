#!/usr/bin/env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Looks for outliers in the 
#################
# TODO:
# Take some sort of tag or group to limit looking for outliers in similar requests
#################

use strict;
use warnings;
use Getopt::Std;
use Math::Complex qw(sqrt);

# Command line params
my %opts = ();
getopts('vi:z:', \%opts);

my $VERBOSE = exists($opts{'v'}) ? 1 : 0;
my @INFILES = defined($opts{'i'}) ? split(/,\s*/, $opts{'i'}, -1) : [];
my $OUTLIER_ZSCORE = defined($opts{'z'}) ? $opts{'z'} : 2;

if (!(@INFILES)) {
   print "$0 -i ./myInputFile.txt\n";
   exit(1);
}

########
# Main #
########

sub main {
   my %reportData;
   foreach my $infile (@INFILES) {
       read_infile($infile, \%reportData);
   }

   # Sort the above records by service.
   my %serviceToReportData;
   foreach my $id (keys(%reportData)) {
      my $service = $reportData{$id}{'service'};
      $serviceToReportData{$service}{$id} = $reportData{$id};
   }

   my %outliers;
   foreach my $service (keys(%serviceToReportData)) {
      find_outliers($serviceToReportData{$service}, \%outliers);
   }

   foreach my $id (sort(keys(%outliers))) {
      #printf("%s: %s", $id, join(', ', sort(values($outliers{$id}))));
      my $outlier_items = join(', ', sort(@{$outliers{$id}}));
      printf("%s: %s\n", $id, $outlier_items);
   }

   return 0;
}

sub standard_dev {
   my (@arrayOfNumbers) = @_;

   my $sum = 0;
   foreach my $num(@arrayOfNumbers) { $sum += $num };
   my $mean = $sum / scalar(@arrayOfNumbers);

   my $sum2 = 0;
   foreach my $num (@arrayOfNumbers) { $sum2 += ($num - $mean)**2 }
   my $variance = $sum2 / scalar(@arrayOfNumbers);

   return (sqrt($variance), $mean);
}

# Just transaction time and return length across all records as of now.
sub find_outliers {
   my ($reportDataRef, $outliersRef) = @_;

   my (%metricsToCheck);
   foreach my $id (keys(%{$reportDataRef})) {
      push(@{$metricsToCheck{'time'}}, ${$reportDataRef}{$id}{'time'});
      push(@{$metricsToCheck{'return length'}}, length(${$reportDataRef}{$id}{'return'}));
      push(@{$metricsToCheck{'error length'}}, length(${$reportDataRef}{$id}{'error'}));
   }

   my (%metricsToStddev);
   foreach my $metric (keys(%metricsToCheck)) {
      @{$metricsToStddev{$metric}} = standard_dev(@{$metricsToCheck{$metric}});
   }

   foreach my $id (keys(%{$reportDataRef})) {
      my ($timeStddev, $timeMean) = @{$metricsToStddev{'time'}};
      push(@{${$outliersRef}{$id}}, 'time') if ($timeStddev && (abs((${$reportDataRef}{$id}{'time'} - $timeMean) / $timeStddev) >= $OUTLIER_ZSCORE));

      my ($returnStddev, $returnMean) = @{$metricsToStddev{'return length'}};
      push(@{${$outliersRef}{$id}}, 'return length') if ($returnStddev && (abs((length(${$reportDataRef}{$id}{'return'}) - $returnMean) / $returnStddev) >= $OUTLIER_ZSCORE));

      my ($errorStddev, $errorMean) = @{$metricsToStddev{'error length'}};
      push(@{${$outliersRef}{$id}}, 'error length') if ($errorStddev && (abs((length(${$reportDataRef}{$id}{'error'}) - $errorMean) / $errorStddev) >= $OUTLIER_ZSCORE));
   }
   return(0);
}

sub read_infile {
   my ($infile, $reportData_ref) = @_;

   printf("Reading: %s\n", $infile) if ($VERBOSE);
   if (open(my $infile_h, '<', $infile)) {
      while(my $line = <$infile_h>) {
         chomp($line);
         # Like: 12341234|return: xxxx
         $line =~ /^([^\|]+)\|(\w+): (.*)$/;
         my ($id, $tag, $value) = ($1, $2, $3);
         ${$reportData_ref}{$id}{$tag} = $value;
      }
   } else {
      warn(sprintf("Warning, the following file does not exist or is not readable: %s\n", $infile));
   }

   return 0;
}

main();
exit(0);
