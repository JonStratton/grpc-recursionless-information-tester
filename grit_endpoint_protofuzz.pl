#!env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Fuzz a known endpoint / method / proto combo with a wordlist.

use strict;
use warnings;
use threads;
use Getopt::Std;
use Digest::MD5 qw(md5_base64);
use IPC::Open2;
use Time::HiRes qw(time);

# Command line params
my %opts = ();
getopt('gdpt', \%opts);

my @PAYLOAD_FILES = defined($opts{'p'}) ? split( /,\s*/, $opts{'p'} ) : ();
my $THREADS = defined($opts{'t'}) ? $opts{'t'} : 10;
my $DATA    = $opts{'d'};
my $GRPCURL = $opts{'g'};
if (!($THREADS and $DATA and $GRPCURL)) {
   print "$0 -p ~/fuzzdb/attack/all-attacks/all-attacks-unix.txt -d '{\"name\":\"_PAYLOAD_\"}' -g 'grpcurl -plaintext -proto ./helloworld.proto -d @ localhost:50051 helloworld.Greeter/SayHello'\n";
   exit(1);
}

sub main {
   # Load Payloads and break down by threads. Looks like $payloads[thread#]
   my @threads_payloads = load_payloads(@PAYLOAD_FILES);

   # Process workload
   my @threads = ();
   foreach my $thread_num (0..($THREADS-1)) {
      next unless defined($threads_payloads[$thread_num]);
      my @payloads = @{$threads_payloads[$thread_num]};
      push(@threads, threads->create('process_chunk', $DATA, \@payloads));
   }

   # Wait for all the threads to return
   foreach my $thread (@threads) {
      $thread->join();
   }
}

# Load a wordlist and break it down by thread
sub load_payloads {
   my @payload_files = @_;
   my @payloads = ();
   foreach my $payload_file (@payload_files) {
      if (open(my $fh, '<', $payload_file)) {
         my $thread_num = 0;
         while(my $line = <$fh>) {
            chomp($line);
            push(@{$payloads[$thread_num]}, $line);
            $thread_num = ($thread_num+1) % $THREADS;
         }
         close($fh);
      }
   }
   return(@payloads);
}

# Replace "_PAYLOAD_" in DATA for each payload in our wordlist, then send it to grpc_request().
sub process_chunk {
   my ($data, $payloads_ref) = @_;
   foreach my $payload (@{$payloads_ref}) {
      $payload =~ s/"/\\"/g; # Escape " in the payload so it doesnt mess with our json
      my $data_new = $data;
      $data_new =~ s/_PAYLOAD_/$payload/g;
      grpc_request($data_new);
   }
}

# Open grpcurl as pipe for both writing (so we can send our payloads in in a raw form) and for reading. Dump the output in a format we can log.
sub grpc_request {
   my ($data) = @_;
   my $request_hash = md5_base64($data);

   # Open2 for reading and writing pipe
   my $pid = open2(my $chld_out, my $chld_in, $GRPCURL);

   my $start_time = time;
   print $chld_in $data;
   close($chld_in); # Need to close the write pipe or thread will hange!
   my $line = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_out>);
   waitpid( $pid, 0 );

   printf("%s|payload: %s\n", $request_hash, $data);
   printf("%s|return: %s\n", $request_hash, $line);
   printf("%s|time: %f\n", $request_hash, (time - $start_time));
}

main();
exit(0);
