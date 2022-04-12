#!/usr/bin/perl
# Just a POC for now; a wrapper around grpcurl.

use strict;
use warnings;
use threads;
use Getopt::Std;
use Digest::MD5 qw(md5_base64);

my $THREADS = 4;
my $HOST = 'localhost:50051';
my $METHOD = 'helloworld.Greeter/SayHello';
my $DATA = '{"name":"_PAYLOAD1_"}';
my $PROTO = './helloworld.proto';

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

sub load_payloads {
   my @payload_files = @_;
   my @payloads = ();
   my $payload_num = 1;
   foreach my $payload_file (@payload_files) {
      my $payload_name = sprintf('_PAYLOAD%d_', $payload_num);
      my $fh;
      if (open($fh, '<', $payload_file)) {
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

sub process_chunk {
   my ($data, $payloads_ref) = @_;
   foreach my $payload_key (keys(%{$payloads_ref})) {
      foreach my $payload (@{${$payloads_ref}{$payload_key}}) {
         my $data_new = $data;
         $data_new =~ s/$payload_key/$payload/g;
         grpc_request($data_new);
         #print("$data, $payload_key, $payload, $data_new\n");
      }
   }
}

sub grpc_request {
   my ($data) = @_;
   my $request = sprintf('grpcurl -plaintext -proto %s -d \'%s\' %s %s', $PROTO, $data, $HOST, $METHOD );
   my $return = `$request`;
   my $request_hash = md5_base64($request);
   printf("Executing(%s): %s\n", $request_hash, $request);
   printf("Return(%s): %s\n", $request_hash, $return);
}

main();
