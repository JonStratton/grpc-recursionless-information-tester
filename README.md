# grpc-reflectionless-information-tester
A collection of POC scripts to enumerate and fuzz test grpc endpoints that dont use reflection. Currently these are just wrappers around [grpcurl](https://github.com/fullstorydev/grpcurl).

**Scripts**
- [**grit_endpoint_protofuzz.pl**](grit_endpoint_protofuzz.pl) - Fuzz a known endpoint / method / proto combo with a wordlist.
- [**grit_endpoint_methodfuzz.pl**](grit_endpoint_methodfuzz.pl) - Fuzz a known endpoint / package for methods with a wordlist.
- [**grit_endpoint_protodump.pl**](grit_endpoint_protodump.pl) - Try to guess / dump a proto file from a known endpoint / method combo.
- [**grit_proto_to_test.pl**](grit_proto_to_test.pl) - Takes one or more protofiles, and creates a bunch of “grit_endpoint_methodfuzz.pl” tests for each service parameter.
- [**grit_protofuzz_findOutliers.pl**](grit_protofuzz_findOutliers.pl) - Takes the output of “grit_endpoint_methodfuzz.pl” and uses standard deviation to try to find outliers.

**Examples**
This is a demo vulnerable App. Listens on localhost:50051 without TLS (note "-plaintext" in the grpcurl command, and "-g '-plaintext'" perl scripts below").
```
% ruby vuln_service_demo/greeter_server_vuln.rb
```

An example of a normal gRPCurl request against the above service.
```
% grpcurl -plaintext -proto ./vuln_service_demo/protos/helloworld.proto -d '{"name":"World"}' localhost:50051 helloworld.Greeter/SayHello
  "message": "Hello World"
```

Finds other RPCes in a known gRPC endpoint / package / service based on a word-list. For Example, finds "util.Users/List" in "util.Users" if "List" is in the word-list (-w ./myRpcList.txt)
```
% perl grit_endpoint_methodfuzz.pl -w ./myRpcList.txt -g '-plaintext' localhost:50051 util.Users
util.Users/Check
util.Users/List
```

Not yet functional. Will attempt to guess the structure of a proto file of a particular RPC endpoint by hitting it with narrower and narrower data types while checking for errors. 
```
% perl grit_endpoint_protodump.pl localhost:50051 util.Users/Check
```

Convert a local proto file into a bunch of grit_endpoint_protofuzz.pl tests. While this takes the host:port and RPC path, it doesn't act on the remote host.
```
% perl grit_proto_to_test.pl -g '-plaintext' -w ./wordlist.txt -p ./vuln_service_demo/protos/util.proto localhost:50051
grit_endpoint_protofuzz.pl -w ./wordlist.txt -d '{"username":"_PAYLOAD_"}' -g '-plaintext -proto ./vuln_service_demo/protos/util.proto' localhost:50051 util.Users/Check
grit_endpoint_protofuzz.pl -w ./wordlist.txt -d '{"str":"_PAYLOAD_", "dbl":"1", "boo":"true", "int":"1"}' -g '-plaintext -proto ./vuln_service_demo/protos/util.proto' localhost:50051 util.Users/Types
grit_endpoint_protofuzz.pl -w ./wordlist.txt -d '{"str":"a", "dbl":"_PAYLOAD_", "boo":"true", "int":"1"}' -g '-plaintext -proto ./vuln_service_demo/protos/util.proto' localhost:50051 util.Users/Types
...
```

Takes a proto file, wordlist, endpoint, and template of a transaction (containing "_PAYLOAD_"), executes it for each line in the wordlist, and outputs information about the grpcurl request for analysis.
```
% perl grit_endpoint_protofuzz.pl -w ./wordlist.txt -d '{"username":"_PAYLOAD_"}' -g '-plaintext -proto ./vuln_service_demo/protos/util.proto' localhost:50051 util.Users/Check | tee output.txt
...
nntShJIxL3K/vVUZacOEng|service: util.Users/Check
nntShJIxL3K/vVUZacOEng|payload: {"username":"Blah"}
nntShJIxL3K/vVUZacOEng|return: {}
nntShJIxL3K/vVUZacOEng|error: 
nntShJIxL3K/vVUZacOEng|time: 0.019707
9n8yGDFPwEEb3COrcJL3DQ|service: util.Users/Check
9n8yGDFPwEEb3COrcJL3DQ|payload: {"username":"test | sleep 10"}
9n8yGDFPwEEb3COrcJL3DQ|return: {}
9n8yGDFPwEEb3COrcJL3DQ|error: 
9n8yGDFPwEEb3COrcJL3DQ|time: 10.018607
```

Find Outliers in a grit_endpoint_protofuzz.pl report
```
% perl grit_protofuzz_findOutliers.pl -i ./output.txt -z 1.4
9n8yGDFPwEEb3COrcJL3DQ: time
...
```
