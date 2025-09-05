# frozen_string_literal: true

begin
  require 'arrow'
rescue LoadError => e
  raise LoadError, "red-arrow gem is required for Parquet output. Install with: gem install red-arrow"
end

module Mongo
  module Protocol
    # Converts BSON bytes directly to Parquet bytes without creating intermediate Ruby objects
    # This bypasses the normal BSON::Document.from_bson deserialization
    class BsonToParquetConverter
      
      # BSON type constants
      BSON_TYPES = {
        0x01 => :double,      # 64-bit floating point
        0x02 => :string,      # UTF-8 string
        0x03 => :document,    # Embedded document
        0x04 => :array,       # Array
        0x05 => :binary,      # Binary data
        0x07 => :object_id,   # ObjectId
        0x08 => :boolean,     # Boolean
        0x09 => :datetime,    # UTC datetime
        0x0A => :null,        # Null value
        0x10 => :int32,       # 32-bit integer
        0x12 => :int64,       # 64-bit integer
      }.freeze

      def initialize
        @schema_cache = {}
      end

      # Convert BSON buffer directly to Parquet bytes
      # @param buffer [BSON::ByteBuffer] The BSON byte buffer
      # @param options [Hash] Options for conversion
      # @return [String] Parquet-encoded bytes
      def convert_to_parquet(buffer, options = {})
        # Read BSON document structure without creating Ruby objects
        doc_data = parse_bson_structure(buffer)
        
        # Build Arrow schema from BSON structure
        schema = build_arrow_schema(doc_data[:fields])
        
        # Create Arrow arrays directly from BSON bytes
        arrays = build_arrow_arrays(buffer, doc_data, schema)
        
        # Create Arrow Table and serialize to Parquet
        table = Arrow::Table.new(schema, arrays)
        
        # Write to Parquet bytes
        output = StringIO.new
        write_parquet(table, output)
        output.string
      end

      private

      # Parse BSON document structure without creating Ruby objects
      def parse_bson_structure(buffer)
        original_position = buffer.read_position
        buffer.rewind!
        
        doc_size = buffer.get_int32
        fields = {}
        field_order = []
        
        while buffer.read_position < (original_position + doc_size - 1)
          break if buffer.peek_byte == 0x00 # End marker
          
          type_byte = buffer.get_byte
          field_name = buffer.get_cstring
          
          fields[field_name] = {
            type: BSON_TYPES[type_byte] || :unknown,
            position: buffer.read_position
          }
          field_order << field_name
          
          # Skip the value bytes without parsing
          skip_bson_value(buffer, type_byte)
        end
        
        buffer.read_position = original_position
        
        {
          size: doc_size,
          fields: fields,
          field_order: field_order
        }
      end

      # Skip BSON value bytes based on type
      def skip_bson_value(buffer, type_byte)
        case type_byte
        when 0x01 # double
          buffer.read_position += 8
        when 0x02 # string
          string_length = buffer.get_int32
          buffer.read_position += string_length
        when 0x03, 0x04 # document/array
          doc_size = buffer.get_int32
          buffer.read_position += doc_size - 4
        when 0x05 # binary
          binary_length = buffer.get_int32
          buffer.read_position += 1 + binary_length # subtype + data
        when 0x07 # object_id
          buffer.read_position += 12
        when 0x08 # boolean
          buffer.read_position += 1
        when 0x09 # datetime
          buffer.read_position += 8
        when 0x0A # null
          # No additional bytes
        when 0x10 # int32
          buffer.read_position += 4
        when 0x12 # int64
          buffer.read_position += 8
        else
          raise "Unsupported BSON type: #{type_byte.to_s(16)}"
        end
      end

      # Build Arrow schema from BSON field information
      def build_arrow_schema(fields)
        arrow_fields = fields.map do |name, info|
          arrow_type = bson_to_arrow_type(info[:type])
          Arrow::Field.new(name, arrow_type)
        end
        
        Arrow::Schema.new(arrow_fields)
      end

      # Map BSON types to Arrow types
      def bson_to_arrow_type(bson_type)
        case bson_type
        when :double
          Arrow::DoubleDataType.new
        when :string
          Arrow::StringDataType.new
        when :int32
          Arrow::Int32DataType.new
        when :int64
          Arrow::Int64DataType.new
        when :boolean
          Arrow::BooleanDataType.new
        when :datetime
          Arrow::TimestampDataType.new(:milli)
        when :object_id
          Arrow::StringDataType.new # Store ObjectId as hex string
        when :null
          Arrow::NullDataType.new
        when :binary
          Arrow::BinaryDataType.new
        when :document, :array
          Arrow::StringDataType.new # Serialize nested structures as JSON strings
        else
          Arrow::StringDataType.new # Default to string for unknown types
        end
      end

      # Build Arrow arrays directly from BSON buffer
      def build_arrow_arrays(buffer, doc_data, schema)
        arrays = {}
        
        schema.fields.each do |field|
          field_info = doc_data[:fields][field.name]
          arrays[field.name] = extract_field_values(buffer, field_info, field.data_type)
        end
        
        arrays.values
      end

      # Extract field values from BSON buffer for a specific field
      def extract_field_values(buffer, field_info, arrow_type)
        # For now, extract single document - can be extended for arrays of documents
        buffer.read_position = field_info[:position]
        
        case field_info[:type]
        when :double
          value = buffer.get_double
          Arrow::DoubleArray.new([value])
        when :string
          length = buffer.get_int32
          value = buffer.get_bytes(length - 1) # -1 for null terminator
          buffer.read_position += 1 # skip null terminator
          Arrow::StringArray.new([value])
        when :int32
          value = buffer.get_int32
          Arrow::Int32Array.new([value])
        when :int64
          value = buffer.get_int64
          Arrow::Int64Array.new([value])
        when :boolean
          value = buffer.get_byte != 0
          Arrow::BooleanArray.new([value])
        when :datetime
          timestamp = buffer.get_int64
          # Convert BSON datetime (milliseconds since epoch) to Arrow timestamp
          Arrow::TimestampArray.new(:milli, [timestamp])
        when :object_id
          object_id_bytes = buffer.get_bytes(12)
          hex_string = object_id_bytes.unpack1('H*')
          Arrow::StringArray.new([hex_string])
        when :null
          Arrow::NullArray.new(1)
        when :binary
          length = buffer.get_int32
          subtype = buffer.get_byte
          data = buffer.get_bytes(length)
          Arrow::BinaryArray.new([data])
        else
          # For complex types, store as string representation
          Arrow::StringArray.new(["<#{field_info[:type]}>"])
        end
      end

      # Write Arrow table to Parquet format
      def write_parquet(table, output)
        Arrow::ParquetArrowFileWriter.open(output, table.schema) do |writer|
          writer.write_table(table)
        end
      end
    end
  end
end
