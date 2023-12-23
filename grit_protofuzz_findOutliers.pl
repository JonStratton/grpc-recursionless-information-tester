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

   my @outliers;
   foreach my $service (keys(%serviceToReportData)) {
      push(@outliers, find_outliers(%{$serviceToReportData{$service}}));
   }
   printf("Outliers: %s\n", join(', ', @outliers)) if (@outliers);

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
   my (%reportData) = @_;

   my (%metricsToCheck);
   foreach my $id (keys(%reportData)) {
      push(@{$metricsToCheck{'time'}}, $reportData{$id}{'time'});
      push(@{$metricsToCheck{'returnLength'}}, length($reportData{$id}{'return'}));
      push(@{$metricsToCheck{'errorLength'}}, length($reportData{$id}{'error'}));
   }

   my (%metricsToStddev);
   foreach my $metric (keys(%metricsToCheck)) {
      @{$metricsToStddev{$metric}} = standard_dev(@{$metricsToCheck{$metric}});
   }

   my @outliers;
   foreach my $id (keys(%reportData)) {
      my ($timeStddev, $timeMean) = @{$metricsToStddev{'time'}};
      push(@outliers, $id) if ($timeStddev && (abs(($reportData{$id}{'time'} - $timeMean) / $timeStddev) >= $OUTLIER_ZSCORE));

      my ($returnStddev, $returnMean) = @{$metricsToStddev{'returnLength'}};
      push(@outliers, $id) if ($returnStddev && (abs((length($reportData{$id}{'return'}) - $returnMean) / $returnStddev) >= $OUTLIER_ZSCORE));

      my ($errorStddev, $errorMean) = @{$metricsToStddev{'errorLength'}};
      push(@outliers, $id) if ($errorStddev && (abs((length($reportData{$id}{'error'}) - $errorMean) / $errorStddev) >= $OUTLIER_ZSCORE));
   }
   return(@outliers);
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
