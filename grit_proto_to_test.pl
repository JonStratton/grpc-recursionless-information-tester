#!env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Parses a proto file and builds some grpcurl commands.
#################
# TODO:
# Deal with enums. Just make them int32s?
# Deal with messages that contain other messages. RECURSION!! YES!!!
# Deal with maps. No idea.
# Gen gRPCurl OR payloadify for other scripts. Or maybe thats its own script
#################

use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;

# Command line params
my %opts = ();
getopts('p:v', \%opts);

my $VERBOSE = exists($opts{'v'}) ? 1 : 0;
my @PROTOFILES = defined($opts{'p'}) ? split(/,\s*/, $opts{'p'}, -1) : [];
my $ADDRESS   = $ARGV[0];

if (!(@PROTOFILES and $ADDRESS)) {
   print "$0 -p ./helloworld.proto localhost:50051\n";
   exit(1);
}

sub main {
   my (%services, %messages);
   foreach my $protofile (@PROTOFILES) {
       parse_proto_file($protofile, \%services, \%messages);
   }

   foreach my $package (sort(keys(%services))) {
     foreach my $service (sort(keys(%{$services{$package}}))) {
        foreach my $rpc (sort(keys(%{$services{$package}{$service}}))) {
            my $servicePath = sprintf("%s.%s/%s", $package, $service, $rpc);
            my $request   = $services{$package}{$service}{$rpc}{'request'};
            my $protofile = $services{$package}{$service}{$rpc}{'protofile'};

            my @params;
            if (defined($messages{$package}{$request})) {
               foreach my $paramSet (@{$messages{$package}{$request}}) {
                  push(@params, sprintf("\"%s\":\"_%s_\"", ${$paramSet}{'name'}, ${$paramSet}{'type'}));
               }
            }
            my $data = join(', ', @params);

            # grpcurl -plaintext -proto ./protos/util.proto -d '{}' localhost:50051 util.Users/Types
            my $grpcurl_cmd = sprintf("grpcurl -proto %s -d '{%s}' %s %s", $protofile, $data, $ADDRESS, $servicePath);
            printf("%s\n", $grpcurl_cmd);
         }
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
         if ($line =~ /^\s*\/\//) {
            next;
         }

         # "package helloworld;"
         if ($line =~ /^\s*package\s+(.+);/) {
            $package = $1;
         }

         # "service Greeter {", Get the service name. We are in service.
         if (($line =~ /^\s*service\s+(\w+)\s+{/) && !$inService) {
            $inService = $1;
         }

         # "rpc SayHelloStreamReply (HelloRequest) returns (stream HelloReply) {}"
         if (($line =~ /^\s*rpc\s*(\w+)\s+\((.+)\)\s+returns\s*\((.+)\)\s+{}/) && $inService) {
            my ($rpcName, $request, $reply) = ($1, $2, $3);
            # Need to save profofile with the service for later use with grpcurl
            ${$services_ref}{$package}{$inService}{$rpcName} = {'request' => $request, 'reply' => $reply, 'protofile' => $protofile};
         }

         # "message HelloRequest {", Get the message name.
         if (($line =~ /^\s*message\s+(\w+)\s*{/) && !$inMessage) {
            $inMessage = $1;
            ${$messages_ref}{$package}{$inMessage} = [];
         }

         # "string name = 1;"
         if (($line =~ /\s*(\w+)\s*(\w+)\s+=\s+(\d+);/) && $inMessage) {
            my ($type, $name, $pos) = ($1, $2, $3);
            ${${$messages_ref}{$package}{$inMessage}}[$pos - 1] = {'type' => $type, 'name' => $name}
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
