# Parquet Output Feature

This MongoDB Ruby driver has been enhanced with a **Parquet output feature** that allows direct conversion of BSON query results to Parquet bytes without creating intermediate Ruby objects.

## Installation

To use the Parquet output feature, you must install the red-arrow gem:

```bash
gem install red-arrow
```

Or add it to your Gemfile:

```ruby
gem 'red-arrow', '~> 17.0'
```

## Usage

### Basic Example

```ruby
require 'mongo'

client = Mongo::Client.new('mongodb://localhost:27017/test')
collection = client[:users]

# Normal query (returns Ruby objects)
collection.find({}).each { |doc| puts doc }

# Parquet query (returns raw Parquet bytes)
parquet_bytes = collection.find({}, { output_parquet: true })

# Write Parquet data to file
File.open('users.parquet', 'wb') { |f| f.write(parquet_bytes) }
```

### Advanced Usage

```ruby
# Query with filters and Parquet output
parquet_data = collection.find(
  { age: { '$gte' => 21 } },
  { 
    projection: { name: 1, age: 1, email: 1 },
    output_parquet: true 
  }
)

File.write('filtered_users.parquet', parquet_data)
```

## Performance Benefits

### Memory Usage
- **Normal**: Creates Ruby Hash object for each document
- **Parquet**: Direct BSON → Parquet conversion, zero Ruby objects

### Speed
- **Normal**: Ruby object creation + GC overhead
- **Parquet**: Direct memory operations only

### Use Cases
- ETL pipelines
- Data analytics workflows  
- Data lake ingestion
- Integration with Pandas/Spark
- High-throughput data processing

## Type Mapping

| MongoDB Type | Parquet Type | Notes |
|--------------|--------------|-------|
| Double | DOUBLE | Direct mapping |
| String | UTF8 | Direct mapping |
| Int32 | INT32 | Direct mapping |
| Int64 | INT64 | Direct mapping |  
| Boolean | BOOL | Direct mapping |
| Date | TIMESTAMP_MILLIS | MongoDB datetime |
| ObjectId | UTF8 | Hex string representation |
| Binary | BINARY | Raw bytes |
| Document | UTF8 | JSON representation |
| Array | UTF8 | JSON representation |

## Error Handling

If the red-arrow gem is not installed:
```
LoadError: red-arrow gem is required for Parquet output. Install with: gem install red-arrow
```

## Examples

See the `examples/` directory for complete working examples:
- `examples/parquet_output_example.rb` - Basic usage
- `examples/complete_parquet_demo.rb` - Full demonstration

## Implementation Details

The feature works by:
1. Intercepting BSON deserialization at the protocol level
2. Parsing BSON structure without creating Ruby objects
3. Mapping BSON types to Arrow/Parquet schema
4. Converting directly to Parquet bytes using Apache Arrow

Key files:
- `lib/mongo/protocol/bson_to_parquet_converter.rb` - Core converter
- `lib/mongo/protocol/serializers.rb` - Protocol modifications

## Limitations

1. **red-arrow dependency**: Requires separate red-arrow gem installation
2. **Nested structures**: Complex nested documents/arrays stored as JSON strings
3. **Schema per document**: Schema is inferred per document (could be optimized)
4. **Single document focus**: Optimized for one document at a time

## Future Improvements

- Batch processing multiple documents
- Schema caching and reuse
- Better nested structure support
- Streaming large result sets
- Configuration options for type mapping
