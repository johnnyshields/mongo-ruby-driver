#!/usr/bin/env ruby
# frozen_string_literal: true

# Example showing how to use the hacked MongoDB Ruby driver to output Parquet bytes
# instead of Ruby objects from query results.
#
# REQUIREMENTS:
#   gem install red-arrow
#   gem install mongo

require 'mongo'

# Verify red-arrow and red-parquet are available for Parquet support
begin
  require 'arrow'
  require 'parquet'
  puts "✓ red-arrow and red-parquet gems found - Parquet support enabled"
rescue LoadError
  puts "✗ red-arrow and red-parquet gems not found. Install with: gem install red-arrow red-parquet"
  exit 1
end

# Example usage of the hacked driver
def demonstrate_parquet_output
  puts "MongoDB to Parquet Direct Conversion Example"
  puts "=" * 50
  
  # Connect to MongoDB (adjust connection string as needed)
  client = Mongo::Client.new('mongodb://localhost:27017/test')
  collection = client[:users]
  
  # Clear and insert fresh data to ensure we're not using cached results
  puts "Clearing collection and inserting fresh data..."
  collection.drop
  sample_data = [
    { name: "Alice", age: 30, email: "alice@example.com", active: true },
    { name: "Bob", age: 25, email: "bob@example.com", active: false },
    { name: "Charlie", age: 35, email: "charlie@example.com", active: true }
  ]
  result = collection.insert_many(sample_data)
  puts "Inserted #{result.inserted_count} documents"
  
  puts "Querying with normal Ruby object output:"
  puts "-" * 40
  
  # Normal query - returns Ruby objects
  cursor = collection.find({})
  cursor.each do |doc|
    puts doc.inspect
  end
  
  puts "\nQuerying with Parquet output (hacked version):"
  puts "-" * 50
  
  begin
    puts "Executing query with Parquet output..."
    puts "Query: collection.find({}, { execution_options: { output_parquet: true } })"
    puts
    
    # The hack should intercept BSON bytes at the protocol level and convert
    # them directly to Parquet bytes using BsonToParquetConverter
    # WITHOUT creating any intermediate Ruby Hash/Document objects
    
    parquet_data = ""
    document_count = 0
    
    # When output_parquet: true, the protocol deserializers should return
    # raw Parquet bytes instead of Ruby objects
    puts "🔍 DEBUG: About to call collection.find with execution_options"
    view = collection.find({}, { execution_options: { output_parquet: true } })
    puts "🔍 DEBUG: Created view: #{view.class}"
    puts "🔍 DEBUG: View options: #{view.options.inspect}"
    
    puts "🔍 DEBUG: About to call view.each"
    puts "🔍 DEBUG: View.method(:each) = #{view.method(:each)}"
    puts "🔍 DEBUG: View.method(:each).source_location = #{view.method(:each).source_location}"
    puts "🔍 DEBUG: Checking if QueryCache is enabled: #{Mongo::QueryCache.enabled?}"
    
    # Disable query cache to force fresh queries
    Mongo::QueryCache.clear
    
    view.each do |result|
      document_count += 1
      
      if result.is_a?(String) && result.encoding == Encoding::ASCII_8BIT
        # SUCCESS: This is raw Parquet bytes from our BsonToParquetConverter
        # No Ruby objects were created - direct BSON -> Parquet conversion!
        parquet_data += result
        puts "🎉 HACK ACTIVE: Received raw Parquet bytes!"
        puts "   Chunk #{document_count}: #{result.bytesize} bytes"
        puts "   Encoding: #{result.encoding}"
        puts "   Magic: #{result[0..3].unpack('H*').first}" if result.size >= 4
      else
        # Hack not fully integrated - still getting Ruby objects
        puts "❌ HACK NOT ACTIVE: Got Ruby object instead of raw bytes"
        puts "   Type: #{result.class}"
        puts "   This means BSON::Document.from_bson was called instead of BsonToParquetConverter"
        
        # Show what we got vs what we want
        puts "   GOT: #{result.inspect[0..80]}..."
        puts "   WANTED: Raw Parquet bytes (String with ASCII-8BIT encoding)"
      end
    end
    
    # If no Parquet bytes received, show what should have happened
    if parquet_data.empty?
      puts "\n⚠️  No raw Parquet bytes received from protocol layer"
      puts "   The hack should have:"
      puts "   1. Intercepted BSON bytes at Document.deserialize / PayloadZero.deserialize"
      puts "   2. Called BsonToParquetConverter.convert_to_parquet(buffer, options)"
      puts "   3. Returned raw Parquet bytes instead of calling BSON::Document.from_bson"
      puts
      puts "📝 Creating demo Parquet data to show expected output..."
      parquet_data = create_demo_parquet_data(collection)
    end
    
    # Write Parquet bytes to file
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    filename = "mongodb_export_#{timestamp}.parquet"
    
    File.open(filename, 'wb') do |file|
      file.write(parquet_data)
    end
    
    puts "\n✅ SUCCESS: Parquet file created!"
    puts "   📄 Filename: #{filename}"
    puts "   📊 File size: #{parquet_data.bytesize} bytes"
    puts "   🔢 Documents processed: #{document_count}"
    puts
    puts "🚀 Next steps - you can now:"
    puts "   1. Load in Pandas: pd.read_parquet('#{filename}')"
    puts "   2. Query with DuckDB: SELECT * FROM '#{filename}'"
    puts "   3. Process with Spark: spark.read.parquet('#{filename}')"
    puts "   4. View with Parquet tools: parquet-tools cat #{filename}"
    
  rescue => e
    puts "❌ Error during Parquet conversion: #{e.class}: #{e.message}"
    puts "📍 Stack trace:"
    puts e.backtrace.first(10).map { |line| "   #{line}" }.join("\n")
    puts
    puts "This is expected if the protocol hack isn't fully integrated yet."
    puts "The hack modifies MongoDB's protocol layer to output Parquet bytes"
    puts "instead of Ruby objects during BSON deserialization."
  end

ensure
  client&.close
end

# Create demo Parquet data using red-arrow for demonstration
def create_demo_parquet_data(collection)
  # Fetch actual data from MongoDB to convert to Parquet
  puts "   📊 Fetching documents from MongoDB..."
  docs = collection.find({}).limit(100).to_a
  
  if docs.empty?
    puts "   ⚠️  No documents found, creating sample data..."
    docs = [
      { "name" => "Alice", "age" => 30, "active" => true },
      { "name" => "Bob", "age" => 25, "active" => false },
      { "name" => "Charlie", "age" => 35, "active" => true }
    ]
  end
  
  puts "   🔄 Converting #{docs.length} documents to Parquet..."
  
  # Extract fields and create Arrow arrays
  names = docs.map { |d| d["name"] || d[:name] }
  ages = docs.map { |d| d["age"] || d[:age] }  
  actives = docs.map { |d| d["active"] || d[:active] }
  ids = docs.map { |d| (d["_id"] || d[:_id])&.to_s || "unknown" }
  
  # Create Arrow table
  table = Arrow::Table.new(
    "id" => ids,
    "name" => names,
    "age" => ages,
    "active" => actives
  )
  
  # Serialize to Parquet bytes
  output = StringIO.new
  Parquet::ArrowFileWriter.open(output, table.schema) do |writer|
    writer.write_table(table)
  end
  
  puts "   ✅ Parquet conversion complete: #{output.string.bytesize} bytes"
  output.string
end

# Additional helper to show how to write Parquet bytes to file
def write_parquet_to_file(parquet_bytes, filename)
  File.open(filename, 'wb') do |file|
    file.write(parquet_bytes)
  end
  puts "Parquet data written to #{filename}"
end

# Run the demonstration
if __FILE__ == $0
  begin
    demonstrate_parquet_output
  rescue Mongo::Error::NoServerAvailable
    puts "Error: Could not connect to MongoDB server."
    puts "Please ensure MongoDB is running on localhost:27017"
    puts "or modify the connection string in the example."
  end
end
