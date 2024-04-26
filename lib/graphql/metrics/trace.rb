# frozen_string_literal: true

module GraphQL
  module Metrics
    module Trace
      def initialize(**_rest)
        super

        query_or_multiplex = @query || @multiplex
        @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false) if query_or_multiplex
        @parsing_duration = 0.0
      end

      # NOTE: These methods come from the graphql ruby gem and are in "chronological" order based on the phases
      # of execution of the graphql-ruby gem, though old versions of the gem aren't always consistent about this (see
      # https://github.com/rmosolgo/graphql-ruby/issues/3393). Most of them can be run multiple times when
      # multiplexing multiple queries.

      # may not trigger if the query is passed in pre-parsed
      def parse(query_string:)
        return super if @skip_tracing
        capture_parsing_time { super }
      end

      def validate(query:, validate:)
        return super if skip_tracing?(query)
        capture_validation_time(query.context) { super }
      end

      # wraps all `analyze_query`s; only run once
      def analyze_multiplex(multiplex:)
        return super if skip_tracing?(multiplex)
        super
      end

      def analyze_query(query:)
        return super if skip_tracing?(query)
        capture_analysis_time(query.context) { super }
      end

      def execute_query(query:)
        return super if skip_tracing?(query)
        capture_query_start_time(query.context) { super }
      end

      def execute_field(field:, query:, ast_node:, arguments:, object:)
        return super if skip_tracing?(query) || query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        trace_field(GraphQL::Metrics::INLINE_FIELD_TIMINGS, field, query) { super }
      end

      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        return super if skip_tracing?(query) || query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        trace_field(GraphQL::Metrics::LAZY_FIELD_TIMINGS, field, query) { super }
      end

      private

      attr_reader :pre_context

      def skip_tracing?(query_or_multiplex)
        if !defined?(@skip_tracing)
          @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false)
        end

        @skip_tracing
      end

      def capture_parsing_time
        result, duration = GraphQL::Metrics.time { yield }
        @parsing_duration = duration
        result
      end

      # Also consolidates parsing timings (if any) from the `pre_context`
      def capture_validation_time(context)
        result, validation_duration = GraphQL::Metrics.time { yield }

        ns = context.namespace(CONTEXT_NAMESPACE)

        ns[PARSING_DURATION] = @parsing_duration
        ns[VALIDATION_DURATION] = validation_duration

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

      def trace_field(context_key, field, query)
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        start_time = GraphQL::Metrics.current_time_monotonic

        result = yield

        duration = GraphQL::Metrics.current_time_monotonic - start_time

        ns[context_key][field.path] ||= []
        ns[context_key][field.path] << { duration: duration }

        result
      end
    end
  end
end
