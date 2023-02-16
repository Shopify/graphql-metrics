# frozen_string_literal: true

module GraphQL
  module Metrics
    class Tracer
      # NOTE: These constants come from the graphql ruby gem and are in "chronological" order based on the phases
      # of execution of the graphql-ruby gem, though old versions of the gem aren't always consistent about this (see
      # https://github.com/rmosolgo/graphql-ruby/issues/3393). Most of them can be run multiple times when
      # multiplexing multiple queries.
      GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY = 'execute_multiplex' # wraps everything below this line; only run once
      GRAPHQL_GEM_LEXING_KEY = 'lex' # may not trigger if the query is passed in pre-parsed
      GRAPHQL_GEM_PARSING_KEY = 'parse' # may not trigger if the query is passed in pre-parsed
      GRAPHQL_GEM_VALIDATION_KEY = 'validate'
      GRAPHQL_GEM_ANALYZE_MULTIPLEX_KEY = 'analyze_multiplex' # wraps all `analyze_query`s; only run once
      GRAPHQL_GEM_ANALYZE_QUERY_KEY = 'analyze_query'
      GRAPHQL_GEM_EXECUTE_QUERY_KEY = 'execute_query'
      GRAPHQL_GEM_TRACING_FIELD_KEYS = [
        GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
        GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
      ]

      include GraphQL::Metrics::Trace

      def initialize
        # no-op, but don't want the behavior from GraphQL::Metrics::Trace
      end

      def trace(key, data, &block)
        # NOTE: Context doesn't exist yet during lexing, parsing.
        context = data[:query]&.context
        skip_tracing = context&.fetch(GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS, false)
        return yield if skip_tracing

        case key
        when GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY
          return capture_multiplex_start_time(&block)
        when GRAPHQL_GEM_LEXING_KEY
          return capture_lexing_time(&block)
        when GRAPHQL_GEM_PARSING_KEY
          return capture_parsing_time(&block)
        when GRAPHQL_GEM_VALIDATION_KEY
          return capture_validation_time(context, &block)
        when GRAPHQL_GEM_ANALYZE_MULTIPLEX_KEY
          # Ensures that we reset potentially long-lived PreContext objects between multiplexs. We reset at this point
          # since all parsing and validation will be done by this point, and a GraphQL::Query::Context will exist.
          pre_context.reset
          return yield
        when GRAPHQL_GEM_ANALYZE_QUERY_KEY
          return capture_analysis_time(context, &block)
        when GRAPHQL_GEM_EXECUTE_QUERY_KEY
          capture_query_start_time(context, &block)
        when *GRAPHQL_GEM_TRACING_FIELD_KEYS
          return yield if context[SKIP_FIELD_AND_ARGUMENT_METRICS]
          return yield unless GraphQL::Metrics.timings_capture_enabled?(data[:query].context)

          context_key = case key
          when GRAPHQL_GEM_TRACING_FIELD_KEY
            GraphQL::Metrics::INLINE_FIELD_TIMINGS
          when GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY
            GraphQL::Metrics::LAZY_FIELD_TIMINGS
          end

          trace_field(context_key, data[:query], &block)
        else
          return yield
        end
      end
    end
  end
end
