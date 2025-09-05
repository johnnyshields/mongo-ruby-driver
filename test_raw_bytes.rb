#!/usr/bin/env ruby
# frozen_string_literal: true

# Test script to verify the raw bytes hack is working
# This should show EXACTLY what the protocol deserializers are returning

require 'mongo'

def test_raw_bytes_interception
  puts "🧪 Testing Raw Bytes Interception"
  puts "=" * 50
  
  begin
    client = Mongo::Client.new('mongodb://localhost:27017/test_raw')
    collection = client[:test_docs]
    
    # Setup test data
    collection.drop
    test_docs = [
      { name: "Test1", value: 100, active: true },
      { name: "Test2", value: 200, active: false }
    ]
    collection.insert_many(test_docs)
    
    puts "📊 Test Data Setup:"
    puts "   Inserted #{test_docs.length} documents"
    puts
    
    puts "🔍 NORMAL QUERY (should create Ruby objects):"
    puts "   Query: collection.find({})"
    collection.find({}).each_with_index do |doc, i|
      puts "   #{i + 1}. #{doc.class}: #{doc.inspect}"
    end
    puts
    
    puts "🎯 HACKED QUERY (should return raw Parquet bytes):"
    puts "   Query: collection.find({}, { execution_options: { output_parquet: true } })"
    puts "   Expected: Raw Parquet bytes (String, ASCII-8BIT encoding)"
    puts "   NOT Expected: Ruby Hash/BSON::Document objects"
    puts
    
    cursor = collection.find({}, { execution_options: { output_parquet: true } })
    cursor.each_with_index do |result, i|
      puts "   Result #{i + 1}:"
      puts "     Class: #{result.class}"
      puts "     Encoding: #{result.encoding}" if result.respond_to?(:encoding)
      puts "     Size: #{result.bytesize} bytes" if result.respond_to?(:bytesize)
      
      if result.is_a?(String) && result.encoding == Encoding::ASCII_8BIT
        puts "     ✅ SUCCESS: Got raw binary bytes!"
        puts "     Magic bytes: #{result[0..7].unpack('H*').first}" if result.size >= 8
        puts "     This indicates BsonToParquetConverter was called!"
      elsif result.is_a?(Hash) || result.class.to_s.include?('BSON')
        puts "     ❌ FAILED: Got Ruby object instead of raw bytes"
        puts "     Content: #{result.inspect[0..60]}..."
        puts "     This means BSON::Document.from_bson was called instead of our converter"
      else
        puts "     ❓ UNEXPECTED: Got #{result.class}"
        puts "     Value: #{result.inspect[0..60]}..."
      end
      puts
    end
    
    client.close
    
  rescue Mongo::Error::NoServerAvailable
    puts "❌ MongoDB not available"
    puts "   Start MongoDB to test the hack"
  rescue => e
    puts "❌ Error: #{e.class}: #{e.message}"
    puts "   #{e.backtrace.first}"
  end
end

def show_expected_flow
  puts "\n📋 EXPECTED HACK FLOW:"
  puts "=" * 30
  puts "1. collection.find({}, { execution_options: { output_parquet: true } })"
  puts "2. MongoDB returns BSON bytes over network"
  puts "3. Protocol::Message.deserialize receives bytes"
  puts "4. deserialize_field calls Document.deserialize(buffer, { output_parquet: true })"
  puts "5. Document.deserialize checks options[:output_parquet]"
  puts "6. Calls BsonToParquetConverter.convert_to_parquet(buffer, options)"
  puts "7. BsonToParquetConverter:"
  puts "   a. Parses BSON structure without creating Ruby objects"
  puts "   b. Builds Arrow schema from BSON types"
  puts "   c. Extracts values directly into Arrow arrays"
  puts "   d. Serializes to Parquet bytes using red-arrow"
  puts "8. Returns raw Parquet bytes (String, ASCII-8BIT encoding)"
  puts "9. Cursor yields raw bytes instead of Ruby Hash objects"
  puts
  puts "🎯 KEY POINT: NO Ruby Hash/Document objects created!"
  puts "   Raw BSON bytes → Raw Parquet bytes (zero-copy conversion)"
end

if __FILE__ == $0
  test_raw_bytes_interception
  show_expected_flow
end
