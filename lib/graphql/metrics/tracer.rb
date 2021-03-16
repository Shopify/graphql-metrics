# frozen_string_literal: true

module GraphQL
  module Metrics
    class Tracer
      # NOTE: These constants come from the graphql ruby gem.
      GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY = 'execute_multiplex'
      GRAPHQL_GEM_LEXING_KEY = 'lex'
      GRAPHQL_GEM_PARSING_KEY = 'parse'
      GRAPHQL_GEM_VALIDATION_KEY = 'validate'
      GRAPHQL_GEM_ANALYZE_MULTIPLEX_KEY = 'analyze_multiplex'
      GRAPHQL_GEM_ANALYZE_QUERY_KEY = 'analyze_query'
      GRAPHQL_GEM_EXECUTE_QUERY_KEY = 'execute_query'
      GRAPHQL_GEM_TRACING_FIELD_KEYS = [
        GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
        GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
      ]

      def trace(key, data, &block)
        puts "* Tracer.trace(#{key})"

        # NOTE: Context doesn't exist yet during lexing, parsing.
        possible_context = data[:query]&.context

        skip_tracing = possible_context&.fetch(GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS, false)
        return yield if skip_tracing

        case key
        when GRAPHQL_GEM_EXECUTE_MULTIPLEX_KEY
          return capture_multiplex_start_time(&block)
        when GRAPHQL_GEM_LEXING_KEY
          return capture_lexing_time(&block)
        when GRAPHQL_GEM_PARSING_KEY
          return capture_parsing_time(&block)
        when GRAPHQL_GEM_VALIDATION_KEY
          context = possible_context
          return capture_validation_time(context, &block)
        when GRAPHQL_GEM_ANALYZE_MULTIPLEX_KEY
          # Ensures that we reset potentially long-lived PreContext objects between multiplexs. We reset at this point
          # since all parsing and validation will be done by this point, and a GraphQL::Query::Context will exist.
          pre_context.reset
          return yield
        when GRAPHQL_GEM_ANALYZE_QUERY_KEY
          context = possible_context
          return capture_analysis_time(context, &block)
        when GRAPHQL_GEM_EXECUTE_QUERY_KEY
          context = possible_context
          capture_query_start_time(context, &block)
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
        :multiplex_start_time,
        :multiplex_start_time_monotonic,
        :parsing_start_time_offset,
        :parsing_duration,
        :lexing_start_time_offset,
        :lexing_duration
      ) do
        def reset
          self[:multiplex_start_time] = nil
          self[:multiplex_start_time_monotonic] = nil
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

      def capture_multiplex_start_time
        puts "  * Capturing pre_context.multiplex_start_time_* in pre_context"

        pre_context.multiplex_start_time = GraphQL::Metrics.current_time
        pre_context.multiplex_start_time_monotonic = GraphQL::Metrics.current_time_monotonic

        yield
      end

      def capture_lexing_time
        # GraphQL::Query#result fires `lex` before the `execute_multiplex` event, so sometimes
        # `pre_context.multiplex_start_time_monotonic` isn't set.
        lexing_offset_time = pre_context.multiplex_start_time_monotonic || GraphQL::Metrics.current_time_monotonic
        timed_result = GraphQL::Metrics.time(lexing_offset_time) { yield }

        puts "  * Capturing pre_context.lexing_* in pre_context"

        pre_context.lexing_start_time_offset = timed_result.start_time
        pre_context.lexing_duration = timed_result.duration

        timed_result.result
      end

      def capture_parsing_time
        # GraphQL::Query#result fires `parse` before the `execute_multiplex` event, so sometimes
        # `pre_context.multiplex_start_time_monotonic` isn't set.
        parsing_offset_time = pre_context.multiplex_start_time_monotonic || GraphQL::Metrics.current_time_monotonic
        timed_result = GraphQL::Metrics.time(parsing_offset_time) { yield }

        pre_context.parsing_start_time_offset = timed_result.start_time
        pre_context.parsing_duration = timed_result.duration

        puts "  * Capturing pre_context.parsing_* in pre_context"

        timed_result.result
      end

      # Also consolidates parsing timings (if any) from the `pre_context`
      def capture_validation_time(context)
        # Queries may already be lexed and parsed before execution (whether a single query or multiplex).
        # If we don't have those values, use some sane defaults.
        if pre_context.lexing_duration.nil?
          pre_context.lexing_start_time_offset = pre_context.multiplex_start_time
          pre_context.lexing_duration = 0.0
        end
        if pre_context.parsing_duration.nil?
          pre_context.parsing_start_time_offset = pre_context.multiplex_start_time
          pre_context.parsing_duration = 0.0
        end

        timed_result = GraphQL::Metrics.time(pre_context.multiplex_start_time_monotonic) { yield }

        ns = context.namespace(CONTEXT_NAMESPACE)

        ns[MULTIPLEX_START_TIME] = pre_context.multiplex_start_time
        ns[MULTIPLEX_START_TIME_MONOTONIC] = pre_context.multiplex_start_time_monotonic
        ns[LEXING_START_TIME_OFFSET] = pre_context.lexing_start_time_offset
        ns[LEXING_DURATION] = pre_context.lexing_duration
        ns[PARSING_START_TIME_OFFSET] = pre_context.parsing_start_time_offset
        ns[PARSING_DURATION] = pre_context.parsing_duration
        ns[VALIDATION_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[VALIDATION_DURATION] = timed_result.duration

        puts "  * Capturing last pre_context.parsing_*, lexing_* times in this query's context"
        puts "  * Capturing validation time in this query's context"

        timed_result.result
      end

      def capture_analysis_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)

        timed_result = GraphQL::Metrics.time(ns[MULTIPLEX_START_TIME_MONOTONIC]) { yield }

        ns[ANALYSIS_START_TIME_OFFSET] = timed_result.time_since_offset
        ns[ANALYSIS_DURATION] = timed_result.duration

        puts "  * Capturing analysis time in this query's context"

        timed_result.result
      end

      def capture_query_start_time(context)
        ns = context.namespace(CONTEXT_NAMESPACE)
        ns[QUERY_START_TIME] = GraphQL::Metrics.current_time
        ns[QUERY_START_TIME_MONOTONIC] = GraphQL::Metrics.current_time_monotonic

        puts "  * Capturing execute time in this query's context"

        yield

        puts " AFTER capture_query_start_time"
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

        puts "  * Capturing field execution time in this query's context"

        timed_result.result
      end
    end
  end
end
