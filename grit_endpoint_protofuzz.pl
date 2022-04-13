#!env perl
# Just a POC for now; a wrapper around grpcurl.
# perl grit_endpoint_protofuzz.pl -p ~/fuzzdb/attack/all-attacks/all-attacks-unix.txt

use strict;
use warnings;
use threads;
use Getopt::Std;
use Digest::MD5 qw(md5_base64);
use IPC::Open2;

my $THREADS = 10;
my $DATA = '{"name":"_PAYLOAD1_"}';
# Formatted to take data from standard in.
my $GRPCURL = 'grpcurl -plaintext -proto ./helloworld.proto -d @ localhost:50051 helloworld.Greeter/SayHello';

# Command line params
my %opts = ();
getopt('p', \%opts);
my @payload_files = split( /,\s*/, $opts{'p'} );

sub main {
   # Load Payloads and break down by threads. Looks like $payloads[thread#]{'PAYLOAD#'}
   my @threads_payloads = load_payloads(@payload_files);

   # Process workload
   my @threads = ();
   foreach my $thread_num (0..($THREADS-1)) {
      next unless defined($threads_payloads[$thread_num]);
      my %payloads = %{$threads_payloads[$thread_num]};
      push(@threads, threads->create('process_chunk', $DATA, \%payloads));
   }

   # Wait for all the threads to return
   foreach my $thread (@threads) {
      $thread->join();
   }
}

# TODO: split our this read from the thread breakdown. 
sub load_payloads {
   my @payload_files = @_;
   my @payloads = ();
   my $payload_num = 1;
   foreach my $payload_file (@payload_files) {
      my $payload_name = sprintf('_PAYLOAD%d_', $payload_num);
      if (open(my $fh, '<', $payload_file)) {
         my $thread_num = 0;
         while(my $line = <$fh>) {
            chomp($line);
            push(@{$payloads[$thread_num]{$payload_name}}, $line);
            $thread_num = ($thread_num+1) % $THREADS;
         }
         close($fh);
      }
      $payload_num++;
   }
   return(@payloads);
}

# TODO: thread breakdown should look like $payloads[$thread_num][] = ({P1 => blah, P2 = blah}, { etc }) so we can deal with multi payloads

sub process_chunk {
   my ($data, $payloads_ref) = @_;
   foreach my $payload_key (keys(%{$payloads_ref})) {
      foreach my $payload (@{${$payloads_ref}{$payload_key}}) {
         $payload =~ s/"/\\"/g; # Escape " in the payload so it doesnt mess with our json
         my $data_new = $data;
         $data_new =~ s/$payload_key/$payload/g;
         grpc_request($data_new);
      }
   }
}

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
   printf("%s|time: %d\n", $request_hash, (time - $start_time));

}

main();
