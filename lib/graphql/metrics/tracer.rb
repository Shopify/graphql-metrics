# frozen_string_literal: true

module GraphQL
  module Metrics
    class Tracer
      # NOTE: These constants come from the graphql ruby gem.
      GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY = 'execute_multiplex'
      GRAPHQL_GEM_PARSING_KEY = 'parse'
      GRAPHQL_GEM_VALIDATION_KEY = 'validate'
      GRAPHQL_GEM_ANALYZE_KEY = 'analyze_query'
      GRAPHQL_GEM_TRACING_FIELD_KEYS = [
        GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
        GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
      ]

      def trace(key, data, &block)
        # NOTE: Context doesn't exist yet during lexing, parsing.
        possible_context = data[:query]&.context

        skip_tracing = possible_context&.fetch(GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS, false)
        return yield if skip_tracing

        # NOTE: Not all tracing events are handled here, but those that are are handled in this case statement in
        # chronological order.
        case key
        when GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY
          return setup_tracing(&block)
        when GRAPHQL_GEM_PARSING_KEY
          return capture_parsing_time(&block)
        when GRAPHQL_GEM_VALIDATION_KEY
          context = possible_context
          return capture_validation_time(context, &block)
        when GRAPHQL_GEM_ANALYZE_KEY
          context = possible_context
          return capture_analysis_time(context, &block)

        when *GRAPHQL_GEM_TRACING_FIELD_KEYS
          return yield if data[:query].context[SKIP_FIELD_AND_ARGUMENT_METRICS]
          return yield unless GraphQL::Metrics.timings_capture_enabled?(data[:query].context)

          context_key = case key
          when GRAPHQL_GEM_TRACING_FIELD_KEY
            GraphQL::Metrics::INLINE_FIELD_TIMINGS
          when GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY
            GraphQL::Metrics::LAZY_FIELD_TIMINGS
          end

          trace_field(context_key, data, &block)
        else
          return yield
        end
      end

      private

      PreContext = Struct.new(
        :query_start_time,
        :query_start_time_monotonic,
        :parsing_start_time_offset,
        :parsing_duration
      ) do
        def reset_parsing_timings
          self[:parsing_start_time_offset] = nil
          self[:parsing_duration] = nil
        end
      end

      def pre_context
        # NOTE: This is used to store timings from lexing, parsing, validation, before we have a context to store
        # values in. Uses thread-safe Concurrent::ThreadLocalVar to store a set of values per thread.
        @pre_context ||= Concurrent::ThreadLocalVar.new(PreContext.new)
        @pre_context.value
      end

      def setup_tracing
        pre_context.query_start_time = GraphQL::Metrics.current_time
        pre_context.query_start_time_monotonic = GraphQL::Metrics.current_time_monotonic

        yield
      end

      def capture_parsing_time
        timed_result = GraphQL::Metrics.time { yield }

        pre_context.parsing_start_time_offset = timed_result.start_time
        pre_context.parsing_duration = timed_result.duration

        timed_result.result
      end

      def capture_validation_time(context)
        if pre_context.parsing_duration.nil?
          pre_context.parsing_start_time_offset = 0
          pre_context.parsing_duration = 0
        end

        timed_result = GraphQL::Metrics.time(pre_context.query_start_time_monotonic) { yield }

        ns = context.namespace(CONTEXT_NAMESPACE)

        ns[QUERY_START_TIME] = pre_context.query_start_time
        ns[QUERY_START_TIME_MONOTONIC] = pre_context.query_start_time_monotonic
        ns[PARSING_START_TIME_OFFSET] = pre_context.parsing_start_time_offset
        ns[PARSING_DURATION] = pre_context.parsing_duration
        ns[VALIDATION_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[VALIDATION_DURATION] = timed_result.duration

        pre_context.reset_parsing_timings

        timed_result.result
      end

      def capture_analysis_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)

        timed_result = GraphQL::Metrics.time(ns[QUERY_START_TIME_MONOTONIC]) { yield }

        ns[ANALYSIS_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[ANALYSIS_DURATION] = timed_result.duration

        timed_result.result
      end

      def trace_field(context_key, data)
        ns = data[:query].context.namespace(CONTEXT_NAMESPACE)
        query_start_time_monotonic = ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]

        timed_result = GraphQL::Metrics.time(query_start_time_monotonic) { yield }

        path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }
        ns[context_key][path_excluding_numeric_indicies] ||= []
        ns[context_key][path_excluding_numeric_indicies] << {
          start_time_offset: timed_result.time_since_offset, duration: timed_result.duration
        }

        timed_result.result
      end
    end
  end
end
