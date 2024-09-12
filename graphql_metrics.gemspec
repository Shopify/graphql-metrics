require_relative "lib/graphql/metrics/version"

Gem::Specification.new do |spec|
  spec.name          = "graphql-metrics"
  spec.version       = GraphQL::Metrics::VERSION
  spec.authors       = ["Christopher Butcher"]
  spec.email         = ["gems@shopify.com"]

  spec.summary       = 'GraphQL Metrics Extractor'
  spec.description   = <<~DESCRIPTION
    Extract as much much detail as you want from GraphQL queries, served up from your Ruby app and the `graphql` gem.
    Compatible with the `graphql-batch` gem, to extract batch-loaded fields resolution timings.
  DESCRIPTION
  spec.homepage      = 'https://github.com/Shopify/graphql-metrics'
  spec.license       = "MIT"

  spec.required_ruby_version = ">= 2.7"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "graphql", ">= 2.3"
  spec.add_development_dependency "rake", "~> 13.2"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency 'graphql-batch'
  spec.add_development_dependency "activesupport", "~> 6.1.7"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-byebug"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "diffy"
  spec.add_development_dependency "hashdiff"
  spec.add_development_dependency "fakeredis"
  spec.add_development_dependency "minitest-focus"
end
