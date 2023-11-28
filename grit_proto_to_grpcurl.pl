#!env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Parses a proto file and builds some grpcurl commands.

use strict;
use warnings;
use Getopt::Std;

# Command line params
my %opts = ();
getopts('p:v', \%opts);

my $VERBOSE = exists($opts{'v'}) ? 1 : 0;
my $PROTOFILE = $opts{'p'};
my $ADDRESS   = $ARGV[0];

if (!($PROTOFILE and $ADDRESS)) {
   print "$0 -p ./helloworld.proto' localhost:50051\n";
   exit(1);
}

sub main {
   my (%services, %messages);
   my $package = parse_proto_file($PROTOFILE, \%services, \%messages);

   foreach my $service (sort(keys(%services))) {
      foreach my $rpc (sort(keys(%{$services{$service}}))) {
          my $servicePath = sprintf("%s.%s/%s", $package, $service, $rpc);
          my $request = $services{$service}{$rpc}{'request'};

          my @params;
          if (defined($messages{$request})) {
             foreach my $paramSet (@{$messages{$request}}) {
                push(@params, sprintf("\"%s\":\"__%s__\"", ${$paramSet}{'name'}, ${$paramSet}{'type'}));
             }
          }
          my $data = join(', ', @params);

          # grpcurl -plaintext -proto ./protos/util.proto -d '{}' localhost:50051 util.Users/Types
          my $grpcurl_cmd = sprintf("grpcurl -proto %s -d '{%s}' %s %s", $PROTOFILE, $data, $ADDRESS, $servicePath);
          printf("%s\n", $grpcurl_cmd);
      }
   }
}

# All out ugly proto parsing at the bottom so we dont have to see it.
sub parse_proto_file {
   my ($protofile, $services_ref, $messages_ref) = @_;
   my ($package);
   printf("Reading: %s\n", $protofile) if ($VERBOSE);

   if (open(my $protofile_h, '<', $protofile)) {

      my ($inService, $inMessage);
      while(my $line = <$protofile_h>) {
         chomp($line);

         # "//", just skip this line
         if ($line =~ /\s*\/\//) {
            next;
         }

         # "package helloworld;", just go with the first match.
         if (($line =~ /\s*package\s+(\w+);/) && !$package) {
            $package = $1;
         }

         # "service Greeter {", Get the service name. We are in service.
         if (($line =~ /\s*service\s+(\w+)\s+{/) && !$inService) {
            $inService = $1;
         }

         # "rpc SayHelloStreamReply (HelloRequest) returns (stream HelloReply) {}"
         if (($line =~ /\s*rpc\s+(\w+)\s+\((.+)\)\s+returns\s+\((.+)\)\s+{}/) && $inService) {
            my ($rpcName, $request, $reply) = ($1, $2, $3);
            ${$services_ref}{$inService}{$rpcName} = {'request' => $request, 'reply' => $reply};
         }

         # "message HelloRequest {", Get the message name.
         if (($line =~ /\s*message\s+(\w+)\s*{/) && !$inMessage) {
            $inMessage = $1;
            ${$messages_ref}{$inMessage} = [];
         }

         # "string name = 1;"
         if (($line =~ /\s*(\w+)\s*(\w+)\s+=\s+(\d+);/) && $inMessage) {
            my ($type, $name, $pos) = ($1, $2, $3);
            push(@{${$messages_ref}{$inMessage}}, {'type' => $type, 'name' => $name});
            # TODO, use $pos rather than push
         }

         # "}", close multiline service or message. 
         if ($line =~ /^\s*}\s*$/) {
            undef($inService);
            undef($inMessage)
         }

      }
      close($protofile_h);

   } else {
      warn(sprintf("Warning, the following file does not exist or is not readable: %s\n", $protofile));
   }
   return($package);
}

main();
