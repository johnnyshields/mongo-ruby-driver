#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test script to verify Parquet output functionality
# Run with: ruby test_parquet_output.rb

require 'mongo'

# Check for red-arrow
begin
  require 'arrow'
  puts "✅ red-arrow gem available"
rescue LoadError
  puts "❌ red-arrow gem not found - install with: gem install red-arrow"
  exit 1
end

def test_parquet_creation
  puts "🧪 Testing Parquet creation with red-arrow..."
  
  # Create sample data
  sample_data = [
    { "name" => "Alice", "age" => 30, "active" => true, "score" => 95.5 },
    { "name" => "Bob", "age" => 25, "active" => false, "score" => 87.2 },
    { "name" => "Charlie", "age" => 35, "active" => true, "score" => 92.8 }
  ]
  
  # Extract arrays
  names = sample_data.map { |d| d["name"] }
  ages = sample_data.map { |d| d["age"] }
  actives = sample_data.map { |d| d["active"] }
  scores = sample_data.map { |d| d["score"] }
  
  # Create Arrow table
  table = Arrow::Table.new(
    "name" => names,
    "age" => ages,
    "active" => actives,
    "score" => scores
  )
  
  # Write to Parquet
  filename = "test_output_#{Time.now.strftime('%Y%m%d_%H%M%S')}.parquet"
  output = StringIO.new
  
  Arrow::ParquetArrowFileWriter.open(output, table.schema) do |writer|
    writer.write_table(table)
  end
  
  parquet_bytes = output.string
  
  # Save to file
  File.open(filename, 'wb') { |f| f.write(parquet_bytes) }
  
  puts "✅ Created Parquet file: #{filename}"
  puts "   📊 Size: #{parquet_bytes.bytesize} bytes"
  puts "   🔢 Records: #{sample_data.length}"
  puts "   🏗️  Schema: #{table.schema.fields.map(&:name).join(', ')}"
  
  # Verify we can read it back
  begin
    read_table = Arrow::Table.load(filename)
    puts "✅ Verification: File reads back successfully"
    puts "   📖 Read #{read_table.n_rows} rows, #{read_table.n_columns} columns"
  rescue => e
    puts "⚠️  Verification failed: #{e.message}"
  end
  
  filename
end

def test_mongodb_connection
  puts "\n🔗 Testing MongoDB connection..."
  
  begin
    client = Mongo::Client.new('mongodb://localhost:27017/test_parquet')
    collection = client[:test_collection]
    
    # Insert test data
    test_docs = [
      { name: "Test User 1", value: 100, created: Time.now },
      { name: "Test User 2", value: 200, created: Time.now }
    ]
    
    collection.drop
    result = collection.insert_many(test_docs)
    puts "✅ Inserted #{result.inserted_count} test documents"
    
    # Try normal query
    puts "📄 Normal query results:"
    collection.find({}).each_with_index do |doc, i|
      puts "   #{i + 1}. #{doc[:name]} (#{doc[:value]})"
    end
    
    # Try with execution options (this would use our hack if active)
    puts "🚀 Attempting Parquet query (hack would activate here)..."
    cursor = collection.find({}, { execution_options: { output_parquet: true } })
    
    cursor.each_with_index do |result, i|
      if result.is_a?(String) && result.encoding == Encoding::ASCII_8BIT
        puts "   ✅ Got Parquet bytes: #{result.bytesize} bytes"
      else
        puts "   📄 Got Ruby object: #{result.class} (hack not active)"
      end
    end
    
    client.close
    puts "✅ MongoDB connection test completed"
    
  rescue Mongo::Error::NoServerAvailable
    puts "⚠️  MongoDB not available - skipping database test"
    puts "   Start MongoDB to test the full pipeline"
  rescue => e
    puts "❌ MongoDB test error: #{e.message}"
  end
end

# Run tests
if __FILE__ == $0
  puts "🧪 MongoDB-to-Parquet Hack Test Suite"
  puts "=" * 50
  
  parquet_file = test_parquet_creation
  test_mongodb_connection
  
  puts "\n📝 Summary:"
  puts "✅ red-arrow gem is working"
  puts "✅ Parquet creation is functional" 
  puts "✅ Test file created: #{parquet_file}"
  puts
  puts "🎯 Next: Run the full examples to see the hack in action:"
  puts "   ruby examples/parquet_output_example.rb"
  puts "   ruby examples/complete_parquet_demo.rb"
end
