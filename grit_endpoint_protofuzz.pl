#!env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Fuzz a known endpoint / method / proto combo with a wordlist.

use strict;
use warnings;
use threads;
use Getopt::Std;
use Digest::MD5 qw(md5_base64);
use IPC::Open3;
use Symbol 'gensym';
use Time::HiRes qw(time);

# Command line params
my %opts = ();
getopt('gdwt', \%opts);

my $WORDLIST = $opts{'w'};
my $THREADS  = defined($opts{'t'}) ? $opts{'t'} : 10;
my $GRPCURL_ARGS = defined($opts{'g'}) ? $opts{'g'} : '';
my $DATA     = $opts{'d'};
my $ADDRESS  = $ARGV[0];
my $SERVICE_NAME = $ARGV[1];

if (!($DATA and $ADDRESS and $SERVICE_NAME)) {
   print "$0 -w ~/fuzzdb/attack/all-attacks/all-attacks-unix.txt -d '{\"name\":\"_PAYLOAD_\"}' -g '-plaintext -proto ./helloworld.proto' localhost:50051 helloworld.Greeter/SayHello\n";
   exit(1);
}

sub main {
   fuzz_proto_main($THREADS, $WORDLIST, $ADDRESS, $SERVICE_NAME, $DATA);
}

sub fuzz_proto_main {
   my ($threads, $wordlist_file, $address, $serviceName, $data) = @_;

   # Load workslists into one big array
   my @wordlist = load_wordlist($wordlist_file);

   # Split wordlist into one array per thread
   my @threads_wordlists = split_list(\@wordlist, $threads);

   # Process workload
   my @threads = ();
   foreach my $thread_num (0..($threads-1)) {
      next unless defined($threads_wordlists[$thread_num]);
      push(@threads, threads->create('fuzz_proto_batch', $address, $serviceName, \@{$threads_wordlists[$thread_num]}, $data));
   }

   # Wait for all the threads to return
   foreach my $thread (@threads) {
      $thread->join();
   }
}

# Replace "_PAYLOAD_" in DATA for each payload in our wordlist, then send it to grpc_request().
sub fuzz_proto_batch {
   my ($address, $serviceName, $payloads_ref, $data) = @_;

   foreach my $payload (@{$payloads_ref}) {
      $payload =~ s/"/\\"/g; # Escape " in the payload so it doesnt mess with our json
      my $data_new = $data;
      $data_new =~ s/_PAYLOAD_/$payload/g;

      my $grpcurl_new = sprintf("grpcurl %s -d @ %s %s", $GRPCURL_ARGS, $address, $serviceName);
      grpcurl_request($grpcurl_new, $data_new);
   }
}

# Split a wordlist into chunks to be processes by a thread
sub split_list {
   my ($list_ref, $chunks) = @_;
   my @lol = ();
   my $chunk_num = 0;
   foreach my $item (@{$list_ref}) {
      push(@{$lol[$chunk_num]}, $item);
      $chunk_num = ($chunk_num+1) % $chunks;
   }
   return(@lol);
}

# Simply read a file and push it into an array
sub load_wordlist {
   my ($wordlist_file) = @_;
   my @wordlist = ();
   if (open(my $wordlist_h, '<', $wordlist_file)) {
      while(my $line = <$wordlist_h>) {
         chomp($line);
         push(@wordlist, $line);
      }
      close($wordlist_h);
   } else {
      warn(sprintf("Warning, the following file does not exist or is not readable: %s\n", $wordlist_file));
   }
   return(@wordlist);
}

# Open grpcurl as pipe for both writing (so we can send our payloads in in a raw form) and for reading. Dump the output in a format we can log.
sub grpcurl_request {
   my ($grpcurl, $data) = @_;
   my $request_hash = md5_base64($data);

   # Open3 for reading and writing pipe
   my ($chld_in, $chld_out, $chld_err, $line, $error);
   $chld_err = gensym;

   open3($chld_in, $chld_out, $chld_err, $grpcurl);

   my $start_time = time;
   print $chld_in $data;
   close($chld_in); # Need to close the write pipe or thread will hange!
   $line = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_out>);
   $error = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_err>);

   printf("%s|payload: %s\n", $request_hash, $data);
   printf("%s|return: %s\n", $request_hash, $line);
   printf("%s|time: %f\n", $request_hash, (time - $start_time));
}

main();
exit(0);
