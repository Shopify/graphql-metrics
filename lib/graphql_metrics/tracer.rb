# frozen_string_literal: true

module GraphQLMetrics
  class Tracer
    # NOTE: Used to store timings from lexing, parsing, validation, before we have a context to store
    # values in. Uses thread-safe Concurrent::ThreadLocalVar to store a set of values per thread.
    cattr_accessor :pre_context

    # NOTE: These constants come from the graphql ruby gem.
    GRAPHQL_GEM_LEXING_KEY = 'lex'
    GRAPHQL_GEM_PARSING_KEY = 'parse'
    GRAPHQL_GEM_VALIDATION_KEYS = ['validate', 'analyze_query', 'analyze_multiplex']
    GRAPHQL_GEM_TRACING_FIELD_KEYS = [
      GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field',
      GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
    ]

    def self.trace(key, data, &resolver_block)
      skip_tracing = data[:query]&.context&.fetch(:skip_graphql_metrics_analysis, false)
      return resolver_block.call if skip_tracing

      return setup_tracing_before_lexing(resolver_block) if key == GRAPHQL_GEM_LEXING_KEY
      return capture_parsing_time(resolver_block) if key == GRAPHQL_GEM_PARSING_KEY

      if GRAPHQL_GEM_VALIDATION_KEYS.include?(key)
        context = data[:query]&.context || data[:multiplex].queries.first.context
        return resolver_block.call unless context.query.valid?
        return capture_validation_time(context, resolver_block)
      end

      return resolver_block.call unless GRAPHQL_GEM_TRACING_FIELD_KEYS.include?(key)

      self.pre_context = nil # cattr values no longer needed, everything we need is in context by now.

      context_key = case key
      when GRAPHQL_GEM_TRACING_FIELD_KEY
        GraphQLMetrics::INLINE_FIELD_TIMINGS
      when GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY
        GraphQLMetrics::LAZY_FIELD_TIMINGS
      end

      if GraphQLMetrics.timings_capture_enabled?(data[:query].context)
        trace_field(context_key, data, resolver_block)
      else
        resolver_block.call
      end

    rescue => e
      binding.pry
      puts
    end

    private

    def self.trace_field(context_key, data, resolver_block)
      path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }

      query_start_time_monotonic = data[:query].context.namespace(GraphQLMetrics::CONTEXT_NAMESPACE)[GraphQLMetrics::QUERY_START_TIME_MONOTONIC]

      field_start_time_monotonic = GraphQLMetrics.current_time_monotonic
      field_start_time_offset = field_start_time_monotonic - query_start_time_monotonic

      result = resolver_block.call
      duration = GraphQLMetrics.current_time_monotonic - field_start_time_monotonic

      data[:query].context.namespace(CONTEXT_NAMESPACE).tap do |ns|
        ns[context_key][path_excluding_numeric_indicies] ||= []
        ns[context_key][path_excluding_numeric_indicies] << {
          start_time_offset: field_start_time_offset, duration: duration
        }
      end

      result
    rescue => e
      binding.pry
      puts
    end

    def self.setup_tracing_before_lexing(resolver_block)
      # NOTE: `before_query` and `initialize` run after trace w/ `lex` key
      # It seems the only alternative to starting query timing here would be to ask users to pass wall / monotonic
      # clock times in their query context. Seems like a worse experience than us just assuming query start times
      # begin in lexing phase.

      # See http://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/ThreadLocalVar.html
      # Using this to overcome issue of using cattr.
      self.pre_context = Concurrent::ThreadLocalVar.new(OpenStruct.new)
      self.pre_context.value.query_start_time = GraphQLMetrics.current_time
      self.pre_context.value.query_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      resolver_block.call
    rescue => e
      binding.pry
      puts
    end

    def self.capture_parsing_time(resolver_block)
      # NOTE: Need to store timings on class attributes, since there's no query context available during parsing.

      parsing_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      self.pre_context.value.parsing_start_time_offset =
        parsing_start_time_monotonic - self.pre_context.value.query_start_time_monotonic

      result = resolver_block.call
      self.pre_context.value.parsing_duration = GraphQLMetrics.current_time_monotonic - parsing_start_time_monotonic

      result
    end

    def self.capture_validation_time(context, resolver_block)
      validation_start_time_monotonic = GraphQLMetrics.current_time_monotonic

      validation_start_time_offset =
        validation_start_time_monotonic - self.pre_context.value.query_start_time_monotonic

      result = resolver_block.call

      validation_duration = GraphQLMetrics.current_time_monotonic - validation_start_time_monotonic

      context.namespace(CONTEXT_NAMESPACE).tap do |ns|
        previous_validation_duration = ns[GraphQLMetrics::VALIDATION_DURATION] || 0

        ns[GraphQLMetrics::QUERY_START_TIME] = self.pre_context.value.query_start_time
        ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC] = self.pre_context.value.query_start_time_monotonic
        ns[PARSING_START_TIME_OFFSET] = self.pre_context.value.parsing_start_time_offset
        ns[PARSING_DURATION] = self.pre_context.value.parsing_duration
        ns[VALIDATION_START_TIME_OFFSET] = validation_start_time_offset

        # NOTE: We add up times spent validating the query syntax as well as running all analyzers
        ns[GraphQLMetrics::VALIDATION_DURATION] = validation_duration + previous_validation_duration
      end

      result
    rescue => e
      binding.pry
      puts
    end
  end
end
