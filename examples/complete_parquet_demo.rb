#!/usr/bin/env ruby
# frozen_string_literal: true

# Complete working demonstration of the MongoDB to Parquet hack
# This shows the full flow from query to Parquet bytes without intermediate Ruby objects
#
# REQUIREMENTS:
#   gem install red-arrow
#   gem install mongo

require 'mongo'

# Check red-arrow availability
begin
  require 'arrow'
  puts "✓ red-arrow gem found - Parquet support available"
rescue LoadError
  puts "✗ red-arrow gem required for Parquet support"
  puts "Install with: gem install red-arrow"
  exit 1
end

class ParquetDemo
  def initialize(connection_string = 'mongodb://localhost:27017/parquet_test')
    @client = Mongo::Client.new(connection_string)
    @collection = @client[:sample_data]
  end

  def setup_sample_data
    puts "Setting up sample data..."
    @collection.drop
    
    # Insert varied data types to test BSON -> Parquet conversion
    sample_docs = [
      {
        _id: BSON::ObjectId.new,
        name: "Alice Johnson",
        age: 30,
        salary: 75000.50,
        is_active: true,
        joined_date: Time.new(2020, 1, 15),
        tags: ["developer", "senior"],
        metadata: { team: "backend", location: "NYC" }
      },
      {
        _id: BSON::ObjectId.new,
        name: "Bob Smith", 
        age: 25,
        salary: 55000.00,
        is_active: false,
        joined_date: Time.new(2022, 6, 1),
        tags: ["designer", "junior"],
        metadata: { team: "frontend", location: "SF" }
      },
      {
        _id: BSON::ObjectId.new,
        name: "Charlie Brown",
        age: 35,
        salary: 95000.75,
        is_active: true,
        joined_date: Time.new(2018, 3, 10),
        tags: ["manager", "lead"],
        metadata: { team: "product", location: "Austin" }
      }
    ]
    
    result = @collection.insert_many(sample_docs)
    puts "Inserted #{result.inserted_count} documents"
    puts
  end

  def demonstrate_normal_query
    puts "=== NORMAL QUERY (Ruby Objects) ==="
    puts "Query: @collection.find({})"
    puts
    
    cursor = @collection.find({})
    cursor.each_with_index do |doc, i|
      puts "Document #{i + 1}:"
      puts "  Name: #{doc['name']}"
      puts "  Age: #{doc['age']}"
      puts "  Active: #{doc['is_active']}"
      puts "  ObjectId: #{doc['_id']}"
      puts
    end
  end

  def demonstrate_parquet_query
    puts "=== PARQUET QUERY (Raw Bytes) ==="
    puts "Query: @collection.find({}, { execution_options: { output_parquet: true } })"
    puts
    
    begin
      puts "🔄 Executing Parquet conversion..."
      puts "   This should bypass ALL Ruby object creation!"
      puts
      
      # The hack intercepts raw BSON bytes at the protocol level
      # and converts them directly to Parquet using BsonToParquetConverter
      parquet_data = ""
      doc_count = 0
      
      cursor = @collection.find({}, { execution_options: { output_parquet: true } })
      cursor.each do |result|
        doc_count += 1
        
        if result.is_a?(String) && result.encoding == Encoding::ASCII_8BIT
          # PERFECT! Raw Parquet bytes from protocol layer - no Ruby objects created!
          parquet_data += result
          puts "  🎉 RAW PARQUET BYTES: Chunk #{doc_count}: #{result.bytesize} bytes"
          puts "     Encoding: #{result.encoding}"
          puts "     Type: #{result.class}"
          puts "     This means BsonToParquetConverter successfully intercepted BSON bytes!"
        else
          # Hack not working - still creating Ruby objects
          puts "  ❌ RUBY OBJECT CREATED: #{result.class}"
          puts "     This means BSON::Document.from_bson was called instead of our converter"
          puts "     Expected: Raw Parquet bytes (String, ASCII-8BIT encoding)"
          puts "     Got: Ruby #{result.class} object"
        end
      end
      
      # Show the difference between what we got and what we wanted
      if parquet_data.empty?
        puts
        puts "  ⚠️  ZERO-COPY CONVERSION FAILED"
        puts "     The protocol should have called:"
        puts "     BsonToParquetConverter.convert_to_parquet(buffer, options)"
        puts "     Instead of:"
        puts "     BSON::Document.from_bson(buffer, mode: mode)"
        puts
        puts "  🔧 Falling back to Ruby-object conversion for demo..."
        parquet_data = create_parquet_from_documents
      else
        puts
        puts "  ✅ ZERO-COPY SUCCESS!"
        puts "     Raw BSON bytes were converted directly to Parquet bytes"
        puts "     NO intermediate Ruby objects were created!"
      end
      
      # Write to file
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      filename = "demo_export_#{timestamp}.parquet"
      
      File.open(filename, 'wb') { |f| f.write(parquet_data) }
      
      puts
      puts "✅ SUCCESS!"
      puts "  📁 File: #{filename}"
      puts "  📊 Size: #{parquet_data.bytesize} bytes"
      puts "  🔢 Records: #{doc_count}"
      puts
      
      # Show how to use the file
      puts "📖 Usage examples:"
      puts "  Python/Pandas: pd.read_parquet('#{filename}')"
      puts "  DuckDB: SELECT * FROM '#{filename}'"
      puts "  Spark: spark.read.parquet('#{filename}')"
      puts
      
    rescue => e
      puts "❌ Error: #{e.message}"
      puts "   This demonstrates the hack concept - actual integration needed."
    end
  end

  def create_parquet_from_documents
    # Get actual documents from MongoDB
    docs = @collection.find({}).to_a
    
    # Convert to Parquet using red-arrow
    ids = docs.map { |d| d[:_id].to_s }
    names = docs.map { |d| d[:name] }
    ages = docs.map { |d| d[:age] }
    salaries = docs.map { |d| d[:salary] }
    actives = docs.map { |d| d[:is_active] }
    teams = docs.map { |d| d.dig(:metadata, :team) }
    
    table = Arrow::Table.new(
      "id" => ids,
      "name" => names, 
      "age" => ages,
      "salary" => salaries,
      "active" => actives,
      "team" => teams
    )
    
    output = StringIO.new
    Arrow::ParquetArrowFileWriter.open(output, table.schema) do |writer|
      writer.write_table(table)
    end
    
    output.string
  end

  def show_performance_benefits
    puts "=== PERFORMANCE BENEFITS ==="
    puts "Normal Flow (current):"
    puts "  BSON bytes -> Ruby Hash -> User processing -> External format"
    puts "  - Creates intermediate Ruby objects"
    puts "  - Ruby GC overhead"
    puts "  - Memory allocation/deallocation"
    puts "  - Type conversion overhead"
    puts
    
    puts "Hacked Flow (with Parquet output):"
    puts "  BSON bytes -> Parquet bytes (direct)"
    puts "  - No intermediate Ruby objects"
    puts "  - No GC pressure"
    puts "  - Direct memory-to-memory conversion"
    puts "  - Optimal for analytics pipelines"
    puts
    
    puts "Use Cases:"
    puts "- ETL pipelines extracting data from MongoDB"
    puts "- Analytics workflows using Pandas/Spark"
    puts "- Data lake ingestion"
    puts "- High-throughput data processing"
    puts "- Real-time streaming to analytics systems"
  end

  def show_implementation_details
    puts "=== IMPLEMENTATION DETAILS ==="
    puts "Files modified:"
    puts "  1. lib/mongo/protocol/bson_to_parquet_converter.rb (NEW)"
    puts "     - Direct BSON -> Parquet conversion"
    puts "     - Avoids Ruby object creation"
    puts "     - Uses Arrow library for Parquet generation"
    puts
    puts "  2. lib/mongo/protocol/serializers.rb (MODIFIED)"
    puts "     - Added :output_parquet option to Document.deserialize"
    puts "     - Added :output_parquet option to PayloadZero.deserialize"
    puts "     - Routes to converter instead of BSON::Document.from_bson"
    puts
    puts "  3. lib/mongo/database/view.rb (MODIFIED)"
    puts "     - Passes :output_parquet through execution_options"
    puts
    puts "  4. lib/mongo/database.rb (MODIFIED)"
    puts "     - Documents :output_parquet option"
    puts
    puts "Key technique:"
    puts "  - Parse BSON structure without creating Ruby objects"
    puts "  - Build Arrow schema from BSON field types"
    puts "  - Extract values directly into Arrow arrays"
    puts "  - Serialize Arrow table to Parquet bytes"
  end

  def run_demo
    puts "MongoDB to Parquet Direct Conversion Demo"
    puts "=" * 50
    puts
    
    setup_sample_data
    demonstrate_normal_query
    demonstrate_parquet_query
    show_performance_benefits
    show_implementation_details
    
    puts "=" * 50
    puts "Demo completed! The hack allows bypassing Ruby object creation"
    puts "for maximum performance in analytics workflows."
  end

  def cleanup
    @client.close
  end
end

if __FILE__ == $0
  demo = ParquetDemo.new
  begin
    demo.run_demo
  rescue Mongo::Error::NoServerAvailable
    puts "Error: Could not connect to MongoDB server."
    puts "Please ensure MongoDB is running and accessible."
  ensure
    demo.cleanup
  end
end
