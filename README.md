# GraphQL Metrics

![](https://github.com/Shopify/graphql-metrics/workflows/Ruby/badge.svg)

Extract as much much detail as you want from GraphQL queries, served up from your Ruby app and the [`graphql` gem](https://github.com/rmosolgo/graphql-ruby).
Compatible with the [`graphql-batch` gem](https://github.com/Shopify/graphql-batch), to extract batch-loaded fields resolution timings.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'graphql-metrics'
```

You can require it with in your code as needed with:
```ruby
require 'graphql_metrics'
```

Or globally in the Gemfile with:
```ruby
gem 'graphql-metrics', require: 'graphql_metrics'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install graphql-metrics

## Usage

Get started by defining your own Analyzer, inheriting from `GraphQLMetrics::Analyzer`.

The following analyzer demonstrates a simple way to capture commonly used metrics sourced from key parts of your schema
definition, the query document being served, as well as runtime query and resolver timings. In this toy example, all of
this data is simply stored on the GraphQL::Query context, under a namespace to avoid collisions with other analyzers
etc.

What you do with these captured metrics is up to you!

### Define your own analyzer subclass

```ruby
  class CaptureAllMetricsAnalyzer < GraphQLMetrics::Analyzer
    ANALYZER_NAMESPACE = :capture_all_metrics_analyzer_namespace

    def initialize(query_or_multiplex)
      super

      # `query` is defined on instances of objects inheriting from GraphQLMetrics::Analyzer
      ns = query.context.namespace(ANALYZER_NAMESPACE)
      ns[:simple_extractor_results] = {}
    end

    # @param metrics [Hash] Query metrics, including a few details about the query document itself, as well as runtime
    # timings metrics, intended to be compatible with the Apollo Tracing spec:
    # https://github.com/apollographql/apollo-tracing#response-format
    #
    # {
    #   operation_type: "query",
    #   operation_name: "PostDetails",
    #   query_start_time: 1573833076.027327,
    #   query_duration: 2.0207119999686256,
    #   parsing_start_time_offset: 0.0010339999571442604,
    #   parsing_duration: 0.0008190000080503523,
    #   validation_start_time_offset: 0.0030819999519735575,
    #   validation_duration: 0.01704599999357015,
    # }
    #
    # You can use these metrics to track high-level query performance, along with any other details you wish to
    # manually capture from `query` and/or `query.context`.
    def query_extracted(metrics)
      custom_metrics_from_context = {
        request_id: query.context[:request_id],
        # ...
      }

      # You can make use of captured metrics here (logging to Kafka, request logging etc.)
      # log_metrics(:fields, metrics)
      #
      # Or store them on the query context:
      store_metrics(:queries, metrics.merge(custom_metrics_from_context))

      # For use after calling query.result, in this case by digging them out, for example in a Rails controller:
      # class GraphQLController < ...
      #   def graph_ql
      #     query_result = graphql_query.result.to_h
      #     do_something_with_metrics(query.context[:simple_extractor_results])
      #     render json: graphql_query.result
      #   end
      # end
    end

    # @param metrics [Hash] Field selection metrics, including resolver timings metrics, also ahering to the
    # Apollo Tracing spec referred to above.

    # `resolver_timings` is populated any time a field is resolved (which may be many times, if the field is nested
    # within a list field e.g. a Relay connection field). There should always be at least one of these per field in
    # a query.
    #
    # `lazy_resolver_timings` is only populated by fields that are resolved lazily (for example using the
    # graphql-batch gem) or that are otherwise resolved with a Promise. Any time spent in the field's resolver to
    # prepare work to be done "later" in a Promise, or batch loader will be captured in `resolver_timings`. The time
    # spent actually doing lazy field loading, including time spent within a batch loader can be obtained from
    # `lazy_resolver_timings`.
    #
    # {
    #   field_name: "id",
    #   return_type_name: "ID",
    #   parent_type_name: "Post",
    #   deprecated: false,
    #   path: ["post", "id"],
    #   resolver_timings: [
    #     start_time_offset: 0.011901999998372048,
    #     duration: 5.999987479299307e-06}
    #   ],
    #   lazy_resolver_timings: nil,
    # }
    def field_extracted(metrics)
      store_metrics(:fields, metrics)
    end

    # @param metrics [Hash] Argument usage metrics, including a few details about the query document itself, as well
    # as resolver timings metrics, also ahering to the Apollo Tracing spec referred to above.
    # {
    #   argument_name: "id",
    #   argument_type_name: "ID",
    #   parent_field_name: "post",
    #   parent_field_type_name: "QueryRoot",
    #   default_used: false,
    #   value_is_null: false,
    #   value: <GraphQL::Query::Arguments::ArgumentValue>,
    # }
    #
    # `value` is exposed here, in case you want to get access to the argument's definition, including the type
    # class which defines it, e.g. `metrics[:value].definition.metadata[:type_class]`
    def argument_extracted(metrics)
      store_metrics(:arguments, metrics)
    end

    private

    def store_metrics(context_key, metrics)
      ns = query.context.namespace(ANALYZER_NAMESPACE)
      ns[:simple_extractor_results][context_key] ||= []
      ns[:simple_extractor_results][context_key] << metrics
    end
  end
```

Once defined, you can opt into capturing all metrics seen above by simply including GraphQLMetrics as a plugin on your
schema.

### Make use of your analyzer

Ensure that your schema is using the graphql-ruby 1.9+ `GraphQL::Execution::Interpreter` and `GraphQL::Analysis::AST`
engine, and then simply add `use GraphQLMetrics, analyzer: SimpleAnalyzer, options: { }`.

(TODO, what options should contain).

This opts you in to capturing all static and runtime metrics seen above.

```ruby
class Schema < GraphQL::Schema
  query QueryRoot
  mutation MutationRoot

  use GraphQL::Execution::Interpreter # Required.
  use GraphQL::Analysis::AST # Required.

  # TODO: This is broken upstream. For now it's:
  # use GraphQLMetrics, analyzer: SimpleAnalyzer, options: {}
  instrument :query, GraphQLMetrics::Instrumentation.new
  query_analyzer SimpleAnalyzer
  tracer GraphQLMetrics::Tracer.new

  use GraphQL::Batch # Optional, but highly recommended. See https://github.com/Shopify/graphql-batch/.
end
```

### Optionally, only gather static metrics

If you don't care to capture runtime metrics like query and resolver timings, you can use your analyzer a standalone
analyzer without `GraphQLMetrics::Instrumentation` and `tracer GraphQLMetrics::Tracer`, like so:

```ruby
class Schema < GraphQL::Schema
  query QueryRoot
  mutation MutationRoot

  use GraphQL::Execution::Interpreter # Required.
  use GraphQL::Analysis::AST # Required.

  query_analyzer SimpleAnalyzer
end
```

Your analyzer will still be called with `query_extracted`, `field_extracted`, but with timings metrics omitted.
`argument_extracted` will work exactly the same, whether instrumentation and tracing are used or not.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/graphql_metrics. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the GraphQLMetrics project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/graphql-metrics/blob/master/CODE_OF_CONDUCT.md).
