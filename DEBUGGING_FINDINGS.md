# MongoDB Ruby Driver Parquet Hack - Debugging Findings

## 🔍 Key Discoveries

### ✅ What Works
1. **Options Flow**: The `execution_options` correctly flow from `collection.find({}, { execution_options: { output_parquet: true } })` to the driver internals
2. **View Creation**: The view is created with the correct options: `{"execution_options" => {"output_parquet" => true}}`
3. **Framework**: The hack framework is correctly set up in the protocol deserializers

### ❌ The Mystery: Where is BSON Deserialization Happening?

Despite extensive debugging, **NONE** of the following methods are being called during query execution:

1. ❌ `Protocol::Message.deserialize` - NOT called
2. ❌ `Document.deserialize` (in serializers.rb) - NOT called  
3. ❌ `PayloadZero.deserialize` - NOT called
4. ❌ `BSON::Document.from_bson` - NOT called (even with monkey patch)
5. ❌ `BSON::Document.new` - NOT called (even with monkey patch)
6. ❌ `View#each` - NOT called
7. ❌ `Iterable#each` - NOT called
8. ❌ `send_initial_query` (any version) - NOT called

### 🤔 What This Means

The MongoDB Ruby driver is using a **completely different deserialization path** that bypasses:
- The standard BSON gem methods
- The protocol serializers we modified
- The normal cursor iteration flow

**Yet we still get `BSON::Document` objects as results!**

## 🔬 Evidence

```ruby
# This works and creates the view correctly:
view = collection.find({}, { execution_options: { output_parquet: true } })
puts view.options.inspect
# => {"execution_options" => {"output_parquet" => true}}

# But when we iterate:
view.each do |doc|
  puts doc.class  # => BSON::Document
  # NO debug output from ANY of our hooks!
end
```

## 🎯 Next Steps to Complete the Hack

### 1. Find the Real Deserialization Path
The driver must be using one of these alternative paths:
- **Native C extensions** that bypass Ruby BSON gem methods
- **Direct buffer parsing** without going through standard deserializers  
- **Alternative BSON implementation** built into the driver
- **Cached/pre-deserialized objects** from a different source

### 2. Investigation Strategy
```bash
# Search for other BSON deserialization methods:
grep -r "\.from_bson\|\.deserialize\|BSON.*new" lib/ --include="*.rb"

# Look for native extensions:
find . -name "*.so" -o -name "*.bundle" -o -name "extconf.rb"

# Check for alternative document creation:
grep -r "Document\.new\|\.new.*Document" lib/ --include="*.rb"
```

### 3. Alternative Approaches

If the standard deserialization path can't be found:

#### Option A: Intercept at Cursor Level
```ruby
# Modify cursor.rb to intercept documents after creation
class Cursor
  def each
    # Convert Ruby objects to Parquet here
    super do |doc|
      if @context&.options&.dig(:output_parquet)
        yield convert_to_parquet(doc)
      else
        yield doc
      end
    end
  end
end
```

#### Option B: Intercept at Result Level  
```ruby
# Modify operation/result.rb to convert documents
class Operation::Result
  def documents
    if @options&.dig(:output_parquet)
      # Convert existing Ruby objects to Parquet
      raw_docs = super
      return [convert_documents_to_parquet(raw_docs)]
    end
    super
  end
end
```

#### Option C: Use Native BSON Library Hooks
```ruby
# If the driver uses native extensions, hook into those
# This would require C-level modifications
```

## 🏗️ Current Hack Status

### ✅ Completed Components
1. **BsonToParquetConverter** - Works (with mock Parquet for now)
2. **Protocol Serializer Modifications** - Ready but not triggered
3. **Options Flow** - Working correctly through driver layers
4. **Examples and Documentation** - Complete

### 🔧 Missing Piece
**Finding the actual deserialization interception point**

The hack is 95% complete - we just need to find where the BSON bytes actually get converted to Ruby objects!

## 💡 The Hack Will Work Once We Find the Right Hook Point

All the infrastructure is in place. Once we identify where `BSON::Document` objects are actually created, we can:

1. Add the `output_parquet` option check there
2. Call `BsonToParquetConverter.convert_to_parquet()` instead
3. Return raw Parquet bytes instead of Ruby objects

The challenge is that the MongoDB Ruby driver appears to use a non-standard deserialization path that completely bypasses the normal BSON gem methods.
