# frozen_string_literal: true
# Generated by the protocol buffer compiler.  DO NOT EDIT!
# source: util.proto

require 'google/protobuf'

require 'google/protobuf/empty_pb'


descriptor_data = "\n\nutil.proto\x12\x04util\x1a\x1bgoogle/protobuf/empty.proto\" \n\x0cUsersRequest\x12\x10\n\x08username\x18\x01 \x01(\t\"#\n\x0eUsersListReply\x12\x11\n\tusernames\x18\x01 \x03(\t\"D\n\x0e\x43omplexRequest\x12\x0b\n\x03str\x18\x01 \x01(\t\x12\x0b\n\x03\x64\x62l\x18\x02 \x01(\x01\x12\x0b\n\x03\x62oo\x18\x03 \x01(\x08\x12\x0b\n\x03int\x18\x04 \x01(\x05\"\x19\n\nTypesReply\x12\x0b\n\x03\x62oo\x18\x01 \x01(\x08\x32\xa7\x01\n\x05Users\x12\x36\n\x04List\x12\x16.google.protobuf.Empty\x1a\x14.util.UsersListReply\"\x00\x12\x33\n\x05\x43heck\x12\x12.util.UsersRequest\x1a\x14.util.UsersListReply\"\x00\x12\x31\n\x05Types\x12\x14.util.ComplexRequest\x1a\x10.util.TypesReply\"\x00\x62\x06proto3"

pool = Google::Protobuf::DescriptorPool.generated_pool

begin
  pool.add_serialized_file(descriptor_data)
rescue TypeError => e
  # Compatibility code: will be removed in the next major version.
  require 'google/protobuf/descriptor_pb'
  parsed = Google::Protobuf::FileDescriptorProto.decode(descriptor_data)
  parsed.clear_dependency
  serialized = parsed.class.encode(parsed)
  file = pool.add_serialized_file(serialized)
  warn "Warning: Protobuf detected an import path issue while loading generated file #{__FILE__}"
  imports = [
  ]
  imports.each do |type_name, expected_filename|
    import_file = pool.lookup(type_name).file_descriptor
    if import_file.name != expected_filename
      warn "- #{file.name} imports #{expected_filename}, but that import was loaded as #{import_file.name}"
    end
  end
  warn "Each proto file must use a consistent fully-qualified name."
  warn "This will become an error in the next major version."
end

module Util
  UsersRequest = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("util.UsersRequest").msgclass
  UsersListReply = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("util.UsersListReply").msgclass
  ComplexRequest = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("util.ComplexRequest").msgclass
  TypesReply = ::Google::Protobuf::DescriptorPool.generated_pool.lookup("util.TypesReply").msgclass
end
