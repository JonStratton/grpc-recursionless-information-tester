# grpc-reflectionless-information-tester
A collection of POC scripts to enumerate and fuzz test grpc endpoints that dont use reflection. Currently these are just wrappers around [grpcurl](https://github.com/fullstorydev/grpcurl).

**Scripts**
- [**grit_endpoint_protofuzz.pl**](grit_endpoint_protofuzz.pl) - Fuzz a known endpoint / method / proto combo with a wordlist.
- [**grit_endpoint_methodfuzz.pl**](grit_endpoint_methodfuzz.pl) - Fuzz a known endpoint / package for methods with a wordlist.
- [**grit_endpoint_protodump.pl**](grit_endpoint_protodump.pl) - Try to guess / dump a proto file from a known endpoint / method combo.
