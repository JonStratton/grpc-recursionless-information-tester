#!/usr/bin/env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Try to guess / dump a proto file from a known endpoint / method combo.

use strict;
use warnings;
use File::Temp qw(tempfile tempdir);
use IPC::Open3;
use Symbol 'gensym';
use Data::Dumper;

my $MAX_INPUT = 5;
my $MAX_OUTPUT = 5;
#my @DATA_TYPES = qw(int64 string);
my @DATA_TYPES = qw(string int64 bool);
my %TYPE_TO_DEFAULT = ('string'=>'"s"', 'int64'=>'2', 'bool'=>'true');

my $package = 'helloworld';
my $service = 'Greeter';
my $method  = 'SayHello';
my $serviceName = 'helloworld.Greeter/SayHello';
my $address = 'localhost:50051';
my $grpcurlOtherArgs = '-plaintext';

my @inputs  = qw();
my @outputs = qw();

sub main() {

my $temp_dir = tempdir(CLEANUP => 1);
while (scalar(@inputs) < $MAX_INPUT) {
   my $valid_dtype;
   foreach my $dtype (@DATA_TYPES) {
      my @test_inputs = @inputs;
      push(@test_inputs, $dtype);

      # Generate proto file based on @temp_inputs
      my $proto = make_proto($package, $service, $method, \@test_inputs, \@outputs);
      my ($proto_h, $proto_filename) = tempfile(SUFFIX => '.proto', CLEANUP => 0, DIR => $temp_dir);
      print $proto_h $proto;
      close($proto_h);

      # Generate data based on @test_inputs
      my $data = make_data(\@test_inputs);

      # Test proto file. 
      my $grpcurl = sprintf('grpcurl %s -import-path %s -proto %s -d @ %s %s', $grpcurlOtherArgs, $temp_dir, $proto_filename, $address, $serviceName);
      my $return = grpcurl_request($grpcurl, $data);

      # if success, add it to inputs and break. If error / bad type, break for each. If error / no more args, break while
      if ($return) {
         $valid_dtype = $dtype;
         last; # Take the first one.
      }
   }

   #
   if ($valid_dtype) {
      push(@inputs, $valid_dtype);
   } else {
      last;
   }
}

# Feels like this should be in a loop somehow
while (scalar(@outputs) < $MAX_OUTPUT) {
   my $valid_dtype;
   foreach my $dtype (@DATA_TYPES) {
      my @test_outputs = @outputs;
      push(@test_outputs, $dtype);

      # Generate proto file based on @temp_inputs
      my $proto = make_proto($package, $service, $method, \@inputs, \@test_outputs);
      my ($proto_h, $proto_filename) = tempfile(SUFFIX => '.proto', CLEANUP => 1, DIR => $temp_dir);
      print $proto_h $proto;
      close($proto_h);

      # Generate data based on @test_inputs
      my $data = make_data(\@inputs);

      # Test proto file.
      my $grpcurl = sprintf('grpcurl %s -import-path %s -proto %s -d @ %s %s', $grpcurlOtherArgs, $temp_dir, $proto_filename, $address, $serviceName);
      my $return = grpcurl_request($grpcurl, $data);

      # if success, add it to inputs and break. If error / bad type, break for each. If error / no more args, break while
      if ($return) {
         $valid_dtype = $dtype;
         last;
      }
   }

   #
   if ($valid_dtype) {
      push(@outputs, $valid_dtype);
   } else {
      last;
   }
}

my $final_proto = make_proto($package, $service, $method, \@inputs, \@outputs);
my $final_data = make_data(\@inputs);
my $final_grpcurl = sprintf('grpcurl %s -proto ./my_new.proto -d \'%s\' %s %s', $grpcurlOtherArgs, $final_data, $address, $serviceName);

printf("#%s\n%s\n", $final_grpcurl, $final_proto);
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

#print("$data\n");
#print("$grpcurl\n");
#print("$line\n");
#print("$error\n");

return($line);
}

# Generate junk data to test our proto with
sub make_data {
my ($inputs_ref) = @_;

my $data = '{';
my $i = 1;
foreach my $input (@{$inputs_ref}) {
   my $default = defined($TYPE_TO_DEFAULT{$input}) ? $TYPE_TO_DEFAULT{$input} : '0';
   $data .= sprintf("\"x%d\":%s", $i, $default);
   if ($i < scalar(@{$inputs_ref})) { # Last element?
      $data .= ',';
   }
   $i = $i + 1;
}
$data .= '}';

return($data);
}

# Generate a string of a proto file
sub make_proto {
my ($package, $service, $method, $inputs_ref, $outputs_ref) = @_;

my $proto = "syntax = \"proto3\";
package $package;
service $service {
  rpc $method (xRequest) returns (xReply) {}
}
message xRequest {
";

my $input_count = 1;
foreach my $input (@{$inputs_ref}) {
   $proto .= sprintf("   %s x%d = %d;\n", $input, $input_count, $input_count);
   $input_count = $input_count + 1;
}

$proto .= '}
message xReply {
';

my $output_count = 1;
foreach my $output (@{$outputs_ref}) {
   $proto .= sprintf("   %s x%d = %d;\n", $output, $output_count, $output_count);
   $output_count = $output_count + 1;
}

$proto .= '}
';

return($proto);
}

main();
exit(0);
