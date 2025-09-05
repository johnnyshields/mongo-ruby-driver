#!/usr/bin/env ruby
# Test script to validate that our Parquet conversion produces real Parquet files

require 'mongo'
require 'arrow'
require 'parquet'

# Test the converter directly
require_relative 'lib/mongo/protocol/bson_to_parquet_converter'

def test_parquet_conversion
  puts "Testing real Parquet conversion..."
  
  # Connect to MongoDB
  client = Mongo::Client.new('mongodb://localhost:27017/test')
  collection = client[:test_parquet]
  
  # Clear and insert test data
  collection.drop
  test_docs = [
    { name: "Alice", age: 30, score: 95.5, active: true },
    { name: "Bob", age: 25, score: 87.2, active: false },
    { name: "Charlie", age: 35, score: 92.8, active: true }
  ]
  collection.insert_many(test_docs)
  
  # Test the converter directly
  converter = Mongo::Protocol::BsonToParquetConverter.new
  
  # Get real documents and convert
  docs = collection.find({}).to_a
  puts "Retrieved #{docs.length} documents from MongoDB"
  
  # Convert to Parquet
  parquet_bytes = converter.convert_documents_to_parquet(docs)
  puts "Generated #{parquet_bytes.bytesize} bytes of Parquet data"
  
  # Write to file
  filename = "test_output.parquet"
  File.open(filename, 'wb') { |f| f.write(parquet_bytes) }
  puts "Written to #{filename}"
  
  # Try to read it back with Arrow
  begin
    table = Arrow::Table.load(filename)
    puts "✅ Successfully read back Parquet file!"
    puts "   Columns: #{table.schema.fields.map(&:name).join(', ')}"
    puts "   Rows: #{table.n_rows}"
    puts "   Sample data: #{table.to_a.first}" if table.n_rows > 0
  rescue => e
    puts "❌ Failed to read Parquet file: #{e.message}"
  end
  
  client.close
end

if __FILE__ == $0
  test_parquet_conversion
end
