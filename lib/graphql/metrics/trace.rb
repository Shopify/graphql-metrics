# frozen_string_literal: true

module GraphQL
  module Metrics
    module Trace
      PreContext = Struct.new(
        :multiplex_start_time,
        :multiplex_start_time_monotonic,
        :parsing_start_time_offset,
        :parsing_duration,
      )

      def initialize(**_rest)
        super

        query_or_multiplex = @query || @multiplex
        @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false) if query_or_multiplex
        @pre_context = PreContext.new
      end

      # NOTE: These methods come from the graphql ruby gem and are in "chronological" order based on the phases
      # of execution of the graphql-ruby gem, though old versions of the gem aren't always consistent about this (see
      # https://github.com/rmosolgo/graphql-ruby/issues/3393). Most of them can be run multiple times when
      # multiplexing multiple queries.

      # wraps everything below this line; only run once
      def execute_multiplex(multiplex:)
        return super if skip_tracing?(multiplex)
        capture_multiplex_start_time { super }
      end

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

      def capture_multiplex_start_time
        pre_context.multiplex_start_time = GraphQL::Metrics.current_time
        pre_context.multiplex_start_time_monotonic = GraphQL::Metrics.current_time_monotonic

        # Set sane default values for parsing in case parsing is done manually
        # If the `parse` tracing hook fires, these will be replaced by real values
        pre_context.parsing_start_time_offset = pre_context.multiplex_start_time
        pre_context.parsing_duration = 0.0

        yield
      end

      def capture_parsing_time
        timed_result = GraphQL::Metrics.time { yield }

        pre_context.parsing_start_time_offset = timed_result.start_time
        pre_context.parsing_duration = timed_result.duration

        timed_result.result
      end

      # Also consolidates parsing timings (if any) from the `pre_context`
      def capture_validation_time(context)
        timed_result = GraphQL::Metrics.time(pre_context.multiplex_start_time_monotonic) { yield }

        ns = context.namespace(CONTEXT_NAMESPACE)

        ns[MULTIPLEX_START_TIME] = pre_context.multiplex_start_time
        ns[MULTIPLEX_START_TIME_MONOTONIC] = pre_context.multiplex_start_time_monotonic
        ns[PARSING_START_TIME_OFFSET] = pre_context.parsing_start_time_offset
        ns[PARSING_DURATION] = pre_context.parsing_duration
        ns[VALIDATION_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[VALIDATION_DURATION] = timed_result.duration

        timed_result.result
      end

      def capture_analysis_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)

        timed_result = GraphQL::Metrics.time(ns[MULTIPLEX_START_TIME_MONOTONIC]) { yield }

        ns[ANALYSIS_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[ANALYSIS_DURATION] = timed_result.duration

        timed_result.result
      end

      def capture_query_start_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)
        ns[QUERY_START_TIME] = GraphQL::Metrics.current_time
        ns[QUERY_START_TIME_MONOTONIC] = GraphQL::Metrics.current_time_monotonic

        yield
      end

      def trace_field(context_key, field, query)
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        offset_time = ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]
        start_time = GraphQL::Metrics.current_time_monotonic

        result = yield

        duration = GraphQL::Metrics.current_time_monotonic - start_time
        time_since_offset = start_time - offset_time if offset_time

        ns[context_key][field.path] ||= []
        ns[context_key][field.path] << {
          start_time_offset: time_since_offset, duration: duration
        }

        result
      end
    end
  end
end
