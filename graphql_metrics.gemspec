
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "graphql_metrics/version"

Gem::Specification.new do |spec|
  spec.name          = "graphql-metrics"
  spec.version       = GraphQLMetrics::VERSION
  spec.authors       = ["Christopher Butcher"]
  spec.email         = ["gems@shopify.com"]

  spec.summary       = 'GraphQL Metrics Extractor'
  spec.description   = <<~DESCRIPTION
    Extract as much much detail as you want from GraphQL queries, served up from your Ruby app and the `graphql` gem.
    Compatible with the `graphql-batch` gem, to extract batch-loaded fields resolution timings.
  DESCRIPTION
  spec.homepage      = 'https://github.com/Shopify/graphql-metrics'
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.16"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "minitest", "~> 5.0"
  spec.add_development_dependency 'graphql-batch'
  spec.add_development_dependency "graphql", "~> 1.8.2"
  spec.add_development_dependency "activesupport", "~> 5.1.5"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "mocha"
  spec.add_development_dependency "diffy"
  spec.add_development_dependency "fakeredis"
end
