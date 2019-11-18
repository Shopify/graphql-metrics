# frozen_string_literal: true

module GraphQLMetrics
  class Tracer
    # NOTE: Used to store timings from lexing, parsing, validation, before we have a context to store
    # values in. Uses thread-safe Concurrent::ThreadLocalVar to store a set of values per thread.
    cattr_accessor :pre_context

    # NOTE: These constants come from the graphql ruby gem.
    GRAPHQL_GEM_LEXING_KEY = 'lex'
    GRAPHQL_GEM_PARSING_KEY = 'parse'
    GRAPHQL_GEM_VALIDATION_KEYS = ['validate', 'analyze_query']
    GRAPHQL_GEM_TRACING_FIELD_KEYS = [
      GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
      GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
    ]

    # TODO: can we implement this as an instance method? pass options instead of skip in context?
    def self.trace(key, data)
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
        return yield unless GraphQLMetrics.timings_capture_enabled?(data[:query].context)

        self.pre_context = nil

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

    def self.setup_tracing_before_lexing
      self.pre_context = Concurrent::ThreadLocalVar.new(OpenStruct.new)
      self.pre_context.value.query_start_time = GraphQLMetrics.current_time
      self.pre_context.value.query_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      yield
    end

    def self.capture_parsing_time
      # NOTE: Storing pre-validation timings on class attributes, since there's no query context available during
      # parsing phase.

      parsing_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      self.pre_context.value.parsing_start_time_offset =
        parsing_start_time_monotonic - self.pre_context.value.query_start_time_monotonic

      result = yield
      self.pre_context.value.parsing_duration = GraphQLMetrics.current_time_monotonic - parsing_start_time_monotonic

      result
    end

    def self.capture_validation_time(context)
      validation_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      validation_start_time_offset =
        validation_start_time_monotonic - self.pre_context.value.query_start_time_monotonic

      result = yield

      validation_duration = GraphQLMetrics.current_time_monotonic - validation_start_time_monotonic

      ns = context.namespace(CONTEXT_NAMESPACE)
      previous_validation_duration = ns[GraphQLMetrics::VALIDATION_DURATION] || 0

      ns[GraphQLMetrics::QUERY_START_TIME] = self.pre_context.value.query_start_time
      ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC] = self.pre_context.value.query_start_time_monotonic
      ns[PARSING_START_TIME_OFFSET] = self.pre_context.value.parsing_start_time_offset
      ns[PARSING_DURATION] = self.pre_context.value.parsing_duration
      ns[VALIDATION_START_TIME_OFFSET] = validation_start_time_offset

      # NOTE: We add up times spent validating the query syntax as well as running all analyzers.
      # This applies to all tracer steps with keys including GRAPHQL_GEM_VALIDATION_KEYS.
      ns[GraphQLMetrics::VALIDATION_DURATION] = validation_duration + previous_validation_duration

      result
    end

    def self.trace_field(context_key, data)
      path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }

      ns = data[:query].context.namespace(CONTEXT_NAMESPACE)
      query_start_time_monotonic = ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC]

      field_start_time_monotonic = GraphQLMetrics.current_time_monotonic
      field_start_time_offset = field_start_time_monotonic - query_start_time_monotonic

      result = yield
      duration = GraphQLMetrics.current_time_monotonic - field_start_time_monotonic

      ns[context_key][path_excluding_numeric_indicies] ||= []
      ns[context_key][path_excluding_numeric_indicies] << {
        start_time_offset: field_start_time_offset, duration: duration
      }

      result
    end
  end
end
