#!/usr/bin/env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Fuzz a known endpoint / method / proto combo with a wordlist.

use strict;
use warnings;
use threads;
use Getopt::Std;
use IPC::Open3;
use Symbol 'gensym';
use File::Temp qw(tempfile tempdir);

# Command line params
my %opts = ();
getopts('vg:w:t:', \%opts);

my $VERBOSE = exists($opts{'v'}) ? 1 : 0;
my $WORDLIST = $opts{'w'};
my $THREADS  = defined($opts{'t'}) ? $opts{'t'} : 10;
my $GRPCURL_ARGS = defined($opts{'g'}) ? $opts{'g'} : '';
my $ADDRESS  = $ARGV[0];
my $SERVICE_NAME = $ARGV[1];

if (!($WORDLIST and $ADDRESS and $SERVICE_NAME)) {
   print "$0 -w ./common-methods.txt -g '-plaintext' localhost:50051 helloworld.Greeter/SayHello\n";
   exit(1);
}

sub main {
   my @found_methods = fuzz_methods_main($THREADS, $WORDLIST, $ADDRESS, $SERVICE_NAME);
   printf("Found the following: %s\n", join(', ', @found_methods));
}

sub fuzz_methods_main {
   my ($threads, $wordlist_file, $address, $serviceName) = @_;

   # Load workslists into one big array
   my @wordlist = load_wordlist($wordlist_file);

   # Split wordlist into one array per thread
   my @threads_wordlists = split_list(\@wordlist, $threads);

   # Temp Dir to keep /tmp/ clean
   my $temp_dir = tempdir(CLEANUP => 1);

   # Process workload
   my @threads = ();
   foreach my $thread_num (0..($threads-1)) {
      next unless defined($threads_wordlists[$thread_num]); # In case we have more threads than words
      push(@threads, threads->create('fuzz_methods_batch', $address, $serviceName, \@{$threads_wordlists[$thread_num]}, $temp_dir));
   }

   # Wait for all the threads to return
   my @methods = ();
   foreach my $thread (@threads) {
      push(@methods, $thread->join());
   }

   return(@methods);
}

# Create a proto file with method names
sub fuzz_methods_batch {
   my ($address, $serviceName, $payloads_ref, $temp_dir) = @_;
   my @found_methods = ();

   # Ignore method name as we are going to fuzz that
   my ($package, $service) = split_serviceName($serviceName);

   # 1, Create proto file
   my @io = qw(string);
   my $temp_proto = make_proto($package, $service, $payloads_ref, \@io, \@io);
   my ($proto_h, $proto_filename) = tempfile(SUFFIX => '.proto', CLEANUP => 1, DIR => $temp_dir);
   print $proto_h $temp_proto;
   close($proto_h);

   # 2. Execute method with proto file
   foreach my $payload (@{$payloads_ref}) {
      my $grpcurl_new = sprintf("grpcurl %s -import-path %s -proto %s -d @ %s %s.%s/%s", $GRPCURL_ARGS, $temp_dir, $proto_filename, $address, $package, $service, $payload);
      printf("%s\n", $grpcurl_new) if ($VERBOSE);
      my $grpcurl_return = grpcurl_request($grpcurl_new, '{"x1":"1"}');
      if ($grpcurl_return) {
         push(@found_methods, $payload);
      }
   }
   return(@found_methods);
}

sub split_serviceName {
   my ($serviceName) = @_;
   my ($temp,$method) = split(/\//, $serviceName);
   my @package = split(/\./, $temp);
   my $service = pop(@package);
   my $package = join('.', @package);
   return($package, $service, $method);
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

# Generate a string of a proto file. For sanity, maybe replace this with a template
sub make_proto {
   my ($package, $service, $methods_ref, $inputs_ref, $outputs_ref) = @_;

   # Header
   my $proto = sprintf("syntax = \"proto3\";\npackage %s;\nservice %s {\n", $package, $service);

   # Methods
   foreach my $method (@{$methods_ref}) {
      $proto .= sprintf("   rpc %s (xRequest) returns (xReply) {}\n", $method);
   }

   # Inputs
   $proto .= "}\nmessage xRequest {\n";
   my $input_count = 1;
   foreach my $input (@{$inputs_ref}) {
      $proto .= sprintf("   %s x%d = %d;\n", $input, $input_count, $input_count);
      $input_count = $input_count + 1;
   }

   # Outputs
   $proto .= "}\nmessage xReply {\n";
   my $output_count = 1;
   foreach my $output (@{$outputs_ref}) {
      $proto .= sprintf("   %s x%d = %d;\n", $output, $output_count, $output_count);
      $output_count = $output_count + 1;
   }
   $proto .= "}\n";

   return($proto);
}

# Open grpcurl as pipe for both writing (so we can send our payloads in in a raw form) and for reading. Dump the output in a format we can log.
sub grpcurl_request {
   my ($grpcurl, $data) = @_;
   my ($line,$error);

   # Open3 for reading and writing pipe
   my ($chld_in, $chld_out, $chld_err);
   $chld_err = gensym;

   open3($chld_in, $chld_out, $chld_err, $grpcurl);
   print $chld_in $data;
   close($chld_in); # Need to close the write pipe or thread will hange!
   $line = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_out>);
   $error = join('', map{ s/^(\s*)|(\s*)$//g; $_ } <$chld_err>);

   return($line);
}

main();
exit(0);
