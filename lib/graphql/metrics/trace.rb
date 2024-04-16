# frozen_string_literal: true

module GraphQL
  module Metrics
    module Trace
      def initialize(**_rest)
        super

        query_or_multiplex = @query || @multiplex
        @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false) if query_or_multiplex
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
        return super if skip_tracing?(query)
        capture_validation_time(query.context) { super }
      end

      # wraps all `analyze_query`s; only run once
      def analyze_multiplex(multiplex:)
        return super if skip_tracing?(multiplex)
        # Ensures that we reset potentially long-lived PreContext objects between multiplexs. We reset at this point
        # since all parsing and validation will be done by this point, and a GraphQL::Query::Context will exist.
        pre_context.reset
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
        return super unless GraphQL::Metrics.timings_capture_enabled?(query.context)
        trace_field(GraphQL::Metrics::INLINE_FIELD_TIMINGS, query) { super }
      end

      def execute_field_lazy(field:, query:, ast_node:, arguments:, object:)
        return super if skip_tracing?(query) || query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        return super unless GraphQL::Metrics.timings_capture_enabled?(query.context)
        trace_field(GraphQL::Metrics::LAZY_FIELD_TIMINGS, query) { super }
      end

      private

      def skip_tracing?(query_or_multiplex)
        if !defined?(@skip_tracing)
          @skip_tracing = query_or_multiplex.context&.fetch(SKIP_GRAPHQL_METRICS_ANALYSIS, false)
        end

        @skip_tracing
      end

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
          self[:lexing_start_time_offset] = nil
          self[:lexing_duration] = nil
        end
      end

      def pre_context
        # NOTE: This is used to store timings from lexing, parsing, validation, before we have a context to store
        # values in. Uses thread-safe Concurrent::ThreadLocalVar to store a set of values per thread.
        @pre_context ||= Concurrent::ThreadLocalVar.new(PreContext.new)
        @pre_context.value
      end

      def capture_multiplex_start_time
        pre_context.multiplex_start_time = GraphQL::Metrics.current_time
        pre_context.multiplex_start_time_monotonic = GraphQL::Metrics.current_time_monotonic

        yield
      end

      def capture_lexing_time
        timed_result = GraphQL::Metrics.time { yield }

        pre_context.lexing_start_time_offset = timed_result.start_time
        pre_context.lexing_duration = timed_result.duration

        timed_result.result
      end

      def capture_parsing_time
        timed_result = GraphQL::Metrics.time { yield }

        pre_context.parsing_start_time_offset = timed_result.start_time
        pre_context.parsing_duration = timed_result.duration

        timed_result.result
      end

      # Also consolidates parsing timings (if any) from the `pre_context`
      def capture_validation_time(context)
        # Queries may already be lexed and parsed before execution (whether a single query or multiplex).
        # If we don't have those values, use some sane defaults.
        if [nil, 0].include?(pre_context.lexing_duration)
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

      def trace_field(context_key, query)
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        offset_time = ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]
        start_time = GraphQL::Metrics.current_time_monotonic
        path = query.context[:current_path]

        result = yield

        duration = GraphQL::Metrics.current_time_monotonic - start_time
        time_since_offset = start_time - offset_time if offset_time

        path_excluding_numeric_indicies = path.select { |p| p.is_a?(String) }
        ns[context_key][path_excluding_numeric_indicies] ||= []
        ns[context_key][path_excluding_numeric_indicies] << {
          start_time_offset: time_since_offset, duration: duration
        }

        result
      end
    end
  end
end
