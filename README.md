# GraphQL Metrics

![](https://github.com/Shopify/graphql-metrics/workflows/Ruby/badge.svg)

Extract as much detail as you want from GraphQL queries, served up from your Ruby app and the [`graphql` gem](https://github.com/rmosolgo/graphql-ruby).
Compatible with the [`graphql-batch` gem](https://github.com/Shopify/graphql-batch), to extract batch-loaded fields resolution timings.

Be sure to read the [CHANGELOG](CHANGELOG.md) to stay updated on feature additions, breaking changes made to this gem.

**NOTE**: Not tested with graphql-ruby's multiplexing feature. Metrics may not
be accurate if you execute multiple operations at once.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'graphql-metrics'
```

You can require it with in your code as needed with:
```ruby
require 'graphql/metrics'
```

Or globally in the Gemfile with:
```ruby
gem 'graphql-metrics', require: 'graphql/metrics'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install graphql-metrics

## Usage

Get started by writing a metrics processor class, inheriting from `GraphQL::Metrics::Processor`.

What you do with these captured metrics is up to you!

**NOTE**: If any non-`graphql-ruby` gem-related exceptions occur in your application during query document
parsing and validation, **runtime metrics** for queries (like `query_duration`) as well as field
resolver timings (like `resolver_timings`, `lazy_resolver_timings`) **may not be present** in the extracted `metrics` hash.

### Define your own analyzer subclass

```ruby
  class SimpleProcessor < GraphQL::Metrics::Processor
    # @param metrics [Hash] Query metrics, including a few details about the query document itself, as well as runtime
    # timings metrics, intended to be compatible with the Apollo Tracing spec:
    # https://github.com/apollographql/apollo-tracing#response-format
    #
    # {
    #   operation_type: "query",
    #   operation_name: "PostDetails",
    #   query_start_time: 1573833076.027327,
    #   query_duration: 2.0207119999686256,
    #   parsing_duration: 0.0008190000080503523,
    #   validation_duration: 0.01704599999357015,
    #   analysis_duration: 0.0008190000080503523,
    # }
    #
    # You can use these metrics to track high-level query performance, along with any other details you wish to
    # manually capture from `query` and/or `query.context`.
    def query_extracted(metric, query:)
      custom_metrics_from_context = {
        request_id: query.context[:request_id],
        # ...
      }

      # You can make use of captured metrics here (logging to Kafka, request logging etc.)
      # log_metrics(:fields, metrics)
      #
      # Or store them on the query context:
      store_metrics(query, :queries, metric.merge(custom_metrics_from_context))
    end

    # For use after controller:
    # class GraphQLController < ActionController::Base
    #   def graphql_query
    #     query_result = graphql_query.result.to_h
    #     do_something_with_metrics(query.context[:simple_extractor_results])
    #     render json: graphql_query.result
    #   end
    # end

    # @param metrics [Hash] Field selection metrics, including resolver timings metrics, also adhering to the Apollo
    # Tracing spec referred to above.
    #
    # `resolver_timings` is populated any time a field is resolved (which may be many times, if the field is nested
    # within a list field e.g. a Relay connection field).
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
    #   resolver_timings: [
    #     5.999987479299307e-06,
    #   ],
    #   lazy_resolver_timings: [
    #     5.999987479299307e-06,
    #   ],
    # }
    def field_extracted(metrics, query:)
      store_metrics(query, :fields, metrics)
    end

    # @param metrics [Hash] Directive metrics
    # {
    #   directive_name: "customDirective",
    # }
    def directive_extracted(metrics, query:)
      store_metrics(query, :directives, metrics)
    end

    # @param metrics [Hash] Argument usage metrics, including a few details about the query document itself, as well
    # as resolver timings metrics, also ahering to the Apollo Tracing spec referred to above.
    # {
    #   argument_name: "ids",
    #   argument_type_name: "ID",
    #   parent_name: "comments",
    #   grandparent_type_name: "Post",
    #   grandparent_node_name: "post",
    #   default_used: false,
    #   value_is_null: false,
    #   value: <GraphQL::Query::Arguments::ArgumentValue>,
    # }
    #
    # `value` is exposed here, in case you want to get access to the argument's definition, including the type
    # class which defines it, e.g. `metrics[:value].definition.metadata[:type_class]`
    def argument_extracted(metrics, query:)
      store_metrics(query, :arguments, metrics)
    end

    private

    def store_metrics(query, context_key, metrics)
      query.context[:simple_extractor_results] ||= {
        queries: [],
        fields: [],
        arguments: [],
        directives: [],
      }

      query.context[:simple_extractor_results][key] << value
    end
  end
```

Once defined, you can opt into capturing all metrics seen above by simply including GraphQL::Metrics as a plugin on your
schema.

#### Metrics that are captured for arguments for fields and directives

Let's have a query example

```graphql
query PostDetails($postId: ID!, $commentsTags: [String!] = null, $val: Int!) @customDirective(val: $val) {
  post(id: $postId) {
    title @skip(if: true)
    comments(ids: [1, 2], tags: $commentsTags) {
      id
      body
    }
  }
}
```
These are some of the arguments that are extracted

```ruby
{
  argument_name: "if",                    # argument name
  argument_type_name: "Boolean",          # argument type
  parent_name: "skip",                    # argument belongs to `skip` directive
  grandparent_type_name: "__Directive",   # argument was applied to directive
  grandparent_node_name: "title",         # directive was applied to field title
  default_used: false,                    # check if default value was used
  value_is_null: false,                   # check if value was null
  value: <GraphQL::Execution::Interpreter::ArgumentValue>
}, {
  argument_name: "id",
  argument_name: "ids",
  argument_type_name: "ID",
  parent_name: "comments",                # name of the node that argument was applied to
  grandparent_type_name: "Post",          # grandparent node to uniquely identify which node the argument was applied to
  grandparent_node_name: "post",          # name of grandparend node
  default_used: false,
  value_is_null: false,
  value: <GraphQL::Execution::Interpreter::ArgumentValue>
}, {
  argument_name: "id",
  argument_type_name: "ID",
  parent_name: "post",                   # argument applied to post field
  grandparent_type_name: "QueryRoot",    # post is a QueryRoot
  grandparent_node_name: "query",        # post field is already in the query root
  parent_input_object_type: nil,
  default_used: false,
  value_is_null: false,
  value: <GraphQL::Execution::Interpreter::ArgumentValue>
}, {
  argument_name: "val",
  argument_type_name: "Int",
  parent_name: "customDirective",        # argument belongs to `customDirective` directive
  grandparent_type_name: "__Directive",  # argument was applied to directive
  grandparent_node_name: "query",        # directive was applied to query
  parent_input_object_type: nil,
  default_used: false,
  value_is_null: false,
  value: <GraphQL::Execution::Interpreter::ArgumentValue>
}
```

### Enable metrics on your schema

```ruby
class Schema < GraphQL::Schema
  query QueryRoot
  mutation MutationRoot
  use GraphQL::Metrics
end
```

To enable all features of the gem including timing metrics, use the `capture_timings` option:
Optionally, capture timing metrics

```ruby
class Schema < GraphQL::Schema
  query QueryRoot
  mutation MutationRoot
  use GraphQL::Metrics, capture_timings: true
end
```

## Order of execution

Because of the structure of graphql-ruby's plugin architecture, it may be difficult to build an intuition around the
order in which methods defined on `GraphQL::Metrics::Instrumentation`, `GraphQL::Metrics::Tracer` and subclasses of
`GraphQL::Metrics::Analyzer` run.

Although you ideally will not need to care about these details if you are simply using this gem to gather metrics in
your application as intended, here's a breakdown of the order of execution of the methods involved:

 When used as instrumentation, an analyzer and tracing, the order of execution is usually:

* Tracer.capture_multiplex_start_time
* Tracer.capture_lexing_time
* Tracer.capture_parsing_time
* Instrumentation.before_query (context setup)
* Tracer.capture_validation_time
* Tracer.capture_analysis_time
* Analyzer#initialize (bit more context setup, instance vars setup)
* Analyzer#result
* Tracer.capture_query_start_time
* Tracer.trace_field (n times)
* Instrumentation.after_query (call query and field callbacks, now that we have all static and runtime metrics
  gathered)
* Analyzer#extract_query
* Analyzer#query_extracted
* Analyzer#extract_fields_with_runtime_metrics
  * calls Analyzer#field_extracted n times

When used as a simple analyzer, which doesn't gather or emit any runtime metrics (timings, arg values):
* Analyzer#initialize
* Analyzer#field_extracted n times
* Analyzer#result
* Analyzer#extract_query
* Analyzer#query_extracted

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Shopify/graphql-metrics. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the GraphQL::Metrics project’s codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/graphql-metrics/blob/master/CODE_OF_CONDUCT.md).
