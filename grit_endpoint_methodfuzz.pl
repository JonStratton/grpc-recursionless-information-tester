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
use File::Temp qw(tempfile);
use Symbol qw(gensym);

# Command line params
my %opts = ();
getopt('gptd', \%opts);

my @PAYLOAD_FILES = defined($opts{'p'}) ? split( /,\s*/, $opts{'p'} ) : ();
my $THREADS = defined($opts{'t'}) ? $opts{'t'} : 10;
my $DATA    = $opts{'d'};
my $GRPCURL = $opts{'g'};
if (!($THREADS and $GRPCURL)) {
   print "$0 -p ~/fuzzdb/discovery/common-methods/common-methods.txt -d 'helloworld.Greeter/_PAYLOAD_' -g 'grpcurl -plaintext -import-path /tmp/ -proto %s -d @ localhost:50051 %s'\n";
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
      push(@threads, threads->create('process_chunk', \@payloads));
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

sub make_proto_method {
   my ($payloads_ref) = @_;
   my ($fh, $filename) = tempfile(SUFFIX => '.proto', CLEANUP => 1);

   # Get the package and service name. TODO, but this in a better place
   my ($pre) = split(/\//, $DATA);
   my @package = split(/\./, $pre);
   my $service = pop(@package);
   my $package = join('.', @package);

   print $fh "syntax = \"proto3\";
package $package;
service $service {
";
   # Create base file
   foreach my $method (@{$payloads_ref}) {
      print $fh sprintf("  rpc %s (xRequest) returns (xReply) {}\n", $method);
   }
print $fh '}
message xRequest {
  string x = 1;
}
message xReply {
  string x = 1;
}';

   return($filename);
}

# Create a proto file with method names
sub process_chunk {
   my ($payloads_ref) = @_;

   # 1, Create proto file
   my $temp_proto = make_proto_method($payloads_ref);

   # 2. Execute method with proto file
   foreach my $payload (@{$payloads_ref}) {
      my $data_new = $DATA;
      $data_new =~ s/_PAYLOAD_/$payload/g;
      my $grpcurl_new = sprintf($GRPCURL, $temp_proto, $data_new);
      grpc_request($grpcurl_new, '{"x":"1"}');
   }
}

# Open grpcurl as pipe for both writing (so we can send our payloads in in a raw form) and for reading. Dump the output in a format we can log.
sub grpc_request {
   my ($grpcurl, $data) = @_;

   # Open2 for reading and writing pipe
   my $pid = open2(my $chld_out, my $chld_in, "$grpcurl 2>/dev/null");
   my $start_time = time;
   print $chld_in $data;
   close($chld_in); # Need to close the write pipe or thread will hange!
   my $line = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_out>);
   waitpid( $pid, 0 );
   if ($line) {
      printf("found: %s\n", $grpcurl);
   }
}

main();
exit(0);
