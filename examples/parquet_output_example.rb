#!/usr/bin/env ruby
# frozen_string_literal: true

# Example showing how to use the hacked MongoDB Ruby driver to output Parquet bytes
# instead of Ruby objects from query results.
#
# REQUIREMENTS:
#   gem install red-arrow
#   gem install mongo

require 'mongo'

# Verify red-arrow is available for Parquet support
begin
  require 'arrow'
  puts "✓ red-arrow gem found - Parquet support enabled"
rescue LoadError
  puts "✗ red-arrow gem not found. Install with: gem install red-arrow"
  exit 1
end

# Example usage of the hacked driver
def demonstrate_parquet_output
  puts "MongoDB to Parquet Direct Conversion Example"
  puts "=" * 50
  
  # Connect to MongoDB (adjust connection string as needed)
  client = Mongo::Client.new('mongodb://localhost:27017/test')
  collection = client[:users]
  
  # Insert some sample data if collection is empty
  if collection.count_documents({}) == 0
    puts "Inserting sample data..."
    sample_data = [
      { name: "Alice", age: 30, email: "alice@example.com", active: true },
      { name: "Bob", age: 25, email: "bob@example.com", active: false },
      { name: "Charlie", age: 35, email: "charlie@example.com", active: true }
    ]
    collection.insert_many(sample_data)
  end
  
  puts "Querying with normal Ruby object output:"
  puts "-" * 40
  
  # Normal query - returns Ruby objects
  cursor = collection.find({})
  cursor.each do |doc|
    puts doc.inspect
  end
  
  puts "\nQuerying with Parquet output (hacked version):"
  puts "-" * 50
  
  # To use the Parquet output, we need to pass the option through the execution context
  # This is a demonstration of how the option would flow through the system
  
  # The Parquet bytes would be generated at the protocol level when deserializing
  # instead of creating Ruby objects. Here's how you would trigger it:
  
  # NOTE: This requires modifications to pass options through the entire call chain
  # from the collection query down to the protocol deserializers
  
  puts "To enable Parquet output, you would call:"
  puts "collection.find({}, { execution_options: { output_parquet: true } })"
  puts ""
  puts "This would return raw Parquet bytes instead of Ruby document objects,"
  puts "avoiding all intermediate Ruby object creation for maximum performance."
  puts ""
  puts "The Parquet bytes can then be:"
  puts "1. Written directly to files"
  puts "2. Sent over network"
  puts "3. Loaded into analytics tools like Pandas, Spark, etc."
  puts "4. Queried with Parquet-compatible engines"

ensure
  client&.close
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
