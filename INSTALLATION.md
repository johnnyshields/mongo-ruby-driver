# Installation Guide for Parquet Support

## Quick Start

To use the MongoDB-to-Parquet feature, you need to install the `red-arrow` gem:

```bash
gem install red-arrow
```

## Using with Bundler

Add to your `Gemfile`:

```ruby
gem 'red-arrow', '~> 17.0'
```

Then run:

```bash
bundle install
```

## Alternative Gemfile

You can use the provided `Gemfile.parquet` which includes the red-arrow dependency:

```bash
BUNDLE_GEMFILE=Gemfile.parquet bundle install
```

## Verifying Installation

Test that red-arrow is properly installed:

```ruby
#!/usr/bin/env ruby
require 'arrow'
puts "✓ red-arrow is installed and working!"
puts "Arrow version: #{Arrow::VERSION}"
```

## System Dependencies

The red-arrow gem may require system-level Apache Arrow libraries. On different systems:

### Ubuntu/Debian
```bash
sudo apt update
sudo apt install -y libarrow-dev libparquet-dev
```

### macOS (with Homebrew)
```bash
brew install apache-arrow
```

### CentOS/RHEL
```bash
sudo yum install epel-release
sudo yum install arrow-devel parquet-cpp-devel
```

## Docker Example

```dockerfile
FROM ruby:3.1

# Install Arrow system dependencies
RUN apt-get update && apt-get install -y \
    libarrow-dev \
    libparquet-dev \
    && rm -rf /var/lib/apt/lists/*

# Install gems
RUN gem install red-arrow mongo

COPY . /app
WORKDIR /app

CMD ["ruby", "examples/complete_parquet_demo.rb"]
```

## Troubleshooting

### Error: "cannot load such file -- arrow"
- Solution: Install red-arrow gem: `gem install red-arrow`

### Error: "libarrow.so: cannot open shared object file"
- Solution: Install Apache Arrow system libraries (see above)

### Error: "incompatible library version"
- Solution: Ensure red-arrow gem version matches system Arrow libraries

## Testing the Installation

Run the demo to verify everything is working:

```bash
ruby examples/complete_parquet_demo.rb
```

You should see:
```
✓ red-arrow gem found - Parquet support available
```
