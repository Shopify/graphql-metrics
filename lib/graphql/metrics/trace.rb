# frozen_string_literal: true

module GraphQL
  module Metrics
    module Trace
      def initialize(**_rest)
        super

        query_or_multiplex = @query || @multiplex
        @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false) if query_or_multiplex
        @parsing_duration = 0.0
        @lexing_duration = 0.0
      end

      # NOTE: These methods come from the graphql ruby gem and are in "chronological" order based on the phases
      # of execution of the graphql-ruby gem, though old versions of the gem aren't always consistent about this (see
      # https://github.com/rmosolgo/graphql-ruby/issues/3393). Most of them can be run multiple times when
      # multiplexing multiple queries.

      # may not trigger if the query is passed in pre-parsed
      def lex(query_string:)
        return super if @skip_tracing
        capture_lexing_time { super }
      end

      # may not trigger if the query is passed in pre-parsed
      def parse(query_string:)
        return super if @skip_tracing
        capture_parsing_time { super }
      end

      def validate(query:, validate:)
        return super if skip_tracing_for_query?(query:)
        capture_validation_time(query.context) { super }
      end

      def analyze_query(query:)
        return super if skip_tracing_for_query?(query:)
        capture_analysis_time(query.context) { super }
      end

      def execute_query(query:)
        return super if skip_tracing_for_query?(query:)
        capture_query_start_time(query.context) { super }
      end

      def execute_field(field:, query:, ast_node:, arguments:, object:)
        return super if skip_tracing_for_query?(query:) || query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        return super unless capture_field_timings?(query.context)
        trace_field(GraphQL::Metrics::INLINE_FIELD_TIMINGS, query) { super }
      end

      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        return super if skip_tracing_for_query?(query:) || query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        return super unless capture_field_timings?(query.context)
        trace_field(GraphQL::Metrics::LAZY_FIELD_TIMINGS, query) { super }
      end

      private

      def capture_field_timings?(context)
        if !defined?(@capture_field_timings)
          @capture_field_timings = !!context.namespace(CONTEXT_NAMESPACE)[TIMINGS_CAPTURE_ENABLED]
        end

        @capture_field_timings
      end

      def capture_lexing_time
        result, duration = GraphQL::Metrics.time { yield }
        @lexing_duration = duration
        result
      end

      def capture_parsing_time
        result, duration = GraphQL::Metrics.time { yield }
        @parsing_duration = duration
        result
      end

      # Also consolidates parsing timings (if any)
      def capture_validation_time(context)
        result, duration = GraphQL::Metrics.time { yield }

        ns = context.namespace(CONTEXT_NAMESPACE)
        ns[LEXING_DURATION] = @lexing_duration
        ns[PARSING_DURATION] = @parsing_duration
        ns[VALIDATION_DURATION] = duration

        result
      end

      def capture_analysis_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)

        result, duration = GraphQL::Metrics.time { yield }

        ns[ANALYSIS_DURATION] = duration

        result
      end

      def capture_query_start_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)
        ns[QUERY_START_TIME] = GraphQL::Metrics.current_time
        ns[QUERY_START_TIME_MONOTONIC] = GraphQL::Metrics.current_time_monotonic

        yield
      end

      def trace_field(context_key, query)
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        path = query.context[:current_path]

        result, duration = GraphQL::Metrics.time { yield }

        path_excluding_numeric_indicies = path.select { |p| p.is_a?(String) }
        ns[context_key][path_excluding_numeric_indicies] ||= []
        ns[context_key][path_excluding_numeric_indicies] << duration

        result
      end

      def skip_tracing_for_query?(query:)
        @skip_tracing || query.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false)
      end
    end
  end
end
