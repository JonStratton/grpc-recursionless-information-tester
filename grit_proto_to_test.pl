#!env perl
# https://github.com/JonStratton/grpc-reflectionless-information-tester
# Parses a proto file and builds some grpcurl commands.
#################
# TODO:
# Deal with enums. Just make them int32s?
# Deal with maps. No idea.
#################

use strict;
use warnings;
use Getopt::Std;
use Data::Dumper;

# Command line params
my %opts = ();
getopts('vp:w:', \%opts);

my $VERBOSE = exists($opts{'v'}) ? 1 : 0;
my $WORDLIST = $opts{'w'};
my @PROTOFILES = defined($opts{'p'}) ? split(/,\s*/, $opts{'p'}, -1) : [];
my $ADDRESS   = $ARGV[0];

if (!(@PROTOFILES and $ADDRESS)) {
   print "$0 -p ./helloworld.proto localhost:50051\n";
   exit(1);
}

my %TypesToDefaults = (
   '_string_' => 'a',
   '_int32_' => 1
);

########
# Main #
########

sub main {
   my (%services, %messages);
   foreach my $protofile (@PROTOFILES) {
       parse_proto_file($protofile, \%services, \%messages);
   }

   # Gen test skeleton
   foreach my $package (sort(keys(%services))) {
     foreach my $service (sort(keys(%{$services{$package}}))) {
        foreach my $rpc (sort(keys(%{$services{$package}{$service}}))) {
            my $servicePath = sprintf("%s.%s/%s", $package, $service, $rpc);
            my $request   = $services{$package}{$service}{$rpc}{'request'};
            my $protofile = $services{$package}{$service}{$rpc}{'protofile'};
            my $data_string = params_to_string($request, $messages{$package});
            #printf("grpcurl -proto %s -d '%s' %s %s", $protofile, $data_string, $ADDRESS, $servicePath);

            foreach my $data_test (data_to_tests($data_string)) {
                my $grit_cmd = sprintf("grit_endpoint_protofuzz.pl -w %s -d '%s' -g '-plaintext -proto %s' %s %s", $WORDLIST, $data_test, $protofile, $ADDRESS, $servicePath);
                printf("%s\n", $grit_cmd);
            }
         }
      }
   }
}

# Converts {"blah1":"_string_","blah2":"_string_"} to {"blah1":"_PAYLOAD_","blah2":"a"} and {"blah1":"a","blah2":"_PAYLOAD_"}
sub data_to_tests {
   my ($data_string) = @_;
   
   my @substItems; # A list of the _blah_s
   while($data_string =~ /(_\w+_)/g) { push(@substItems, $1) }

   my @tests;
   foreach my $pos (1..scalar(@substItems)) {
      my $temp_data = $data_string;
      foreach my $pos2 (1..scalar(@substItems)) {
         my $oldValue = $substItems[$pos2-1];
         my $newValue = '_PAYLOAD_';
         if ($pos != $pos2) {
             $newValue = defined($TypesToDefaults{$oldValue}) ? $TypesToDefaults{$oldValue} : 1;
         }
         $temp_data =~ s/$oldValue/$newValue/;
      }
      #$tests[$pos-1] = $temp_data;
      push(@tests, $temp_data);
   }

   return(@tests);
}

# Recursion for nested objects
sub params_to_string {
   my ($message_name, $packMesg_ref) = @_;
   my @params;
   if (defined(${$packMesg_ref}{$message_name})) {
      foreach my $paramSet (@{${$packMesg_ref}{$message_name}}) {
         next unless defined(${$paramSet}{'name'}); # Gaps in numbers in the protofiles
         my $type = ${$paramSet}{'type'};
         # Is type just another object name?

         my $type_string = sprintf("\"_%s_\"", ${$paramSet}{'type'});
         if (defined(${$packMesg_ref}{$type})) {
            $type_string = params_to_string($type, $packMesg_ref);
         }

         push(@params, sprintf("\"%s\":%s", ${$paramSet}{'name'}, $type_string));
      }
   }
   return(sprintf("{%s}", join(', ', @params)));
}

# All our ugly proto parsing at the bottom so we dont have to see it.
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
         if (($line =~ /^\s*rpc\s+(\w+)\s*\((.+)\)\s+returns\s+\((.+)\)\s*{}/) && $inService) {
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
         if (($line =~ /^\s*(\w+)\s+(\w+)\s+=\s+(\d+);/) && $inMessage) {
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
   return(0);
}

main();
-1;
