# frozen_string_literal: true

module GraphQLMetrics
  class Tracer
    # NOTE: Used to store timings from lexing, parsing, validation, before we have a context to store
    # values in. Uses thread-safe Concurrent::ThreadLocalVar to store a set of values per thread.

    # NOTE: These constants come from the graphql ruby gem.
    GRAPHQL_GEM_LEXING_KEY = 'lex'
    GRAPHQL_GEM_PARSING_KEY = 'parse'
    GRAPHQL_GEM_VALIDATION_KEYS = ['validate', 'analyze_query']
    GRAPHQL_GEM_TRACING_FIELD_KEYS = [
      GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
      GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
    ]

    # TODO: pass options instead of skip in context?
    def trace(key, data)
      # NOTE: Context doesn't exist yet during lexing, parsing.
      possible_context = data[:query]&.context

      skip_tracing = possible_context&.fetch(GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS, false)
      return yield if skip_tracing

      # NOTE: Not all tracing events are handled here, but those that are are handled in this case statement in
      # chronological order.
      case key
      when GRAPHQL_GEM_LEXING_KEY
        return setup_tracing_before_lexing { yield }
      when GRAPHQL_GEM_PARSING_KEY
        return capture_parsing_time { yield }
      when *GRAPHQL_GEM_VALIDATION_KEYS
        context = possible_context

        return yield unless context.query.valid?
        return capture_validation_time(context) { yield }
      when *GRAPHQL_GEM_TRACING_FIELD_KEYS
        return yield if data[:query].context[SKIP_FIELD_AND_ARGUMENT_METRICS]
        return yield unless GraphQLMetrics.timings_capture_enabled?(data[:query].context)

        pre_context = nil

        context_key = case key
        when GRAPHQL_GEM_TRACING_FIELD_KEY
          GraphQLMetrics::INLINE_FIELD_TIMINGS
        when GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY
          GraphQLMetrics::LAZY_FIELD_TIMINGS
        end

        trace_field(context_key, data) { yield }
      else
        return yield
      end
    end

    private

    def pre_context
      @pre_context ||= Concurrent::ThreadLocalVar.new(OpenStruct.new)
    end

    def setup_tracing_before_lexing
      pre_context.value.query_start_time = GraphQLMetrics.current_time
      pre_context.value.query_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      yield
    end

    def capture_parsing_time
      timed_result = GraphQLMetrics.time { yield }

      pre_context.value.parsing_start_time_offset = timed_result.start_time
      pre_context.value.parsing_duration = timed_result.duration

      timed_result.result
    end

    def capture_validation_time(context)
      timed_result = GraphQLMetrics.time(pre_context.value.query_start_time_monotonic) { yield }

      ns = context.namespace(CONTEXT_NAMESPACE)
      previous_validation_duration = ns[GraphQLMetrics::VALIDATION_DURATION] || 0

      ns[GraphQLMetrics::QUERY_START_TIME] = pre_context.value.query_start_time
      ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC] = pre_context.value.query_start_time_monotonic
      ns[PARSING_START_TIME_OFFSET] = pre_context.value.parsing_start_time_offset
      ns[PARSING_DURATION] = pre_context.value.parsing_duration
      ns[VALIDATION_START_TIME_OFFSET] = timed_result.time_since_offset
      ns[GraphQLMetrics::VALIDATION_DURATION] = timed_result.duration + previous_validation_duration

      timed_result.result
    end

    def trace_field(context_key, data)
      ns = data[:query].context.namespace(CONTEXT_NAMESPACE)
      query_start_time_monotonic = ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC]

      timed_result = GraphQLMetrics.time(query_start_time_monotonic) { yield }

      path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }
      ns[context_key][path_excluding_numeric_indicies] ||= []
      ns[context_key][path_excluding_numeric_indicies] << {
        start_time_offset: timed_result.time_since_offset, duration: timed_result.duration
      }

      timed_result.result
    end
  end
end
