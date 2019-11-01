require 'concurrent'

module GraphQLMetrics
  class Analyzer < GraphQL::Analysis::AST::Analyzer
    FieldTimingCallback = Struct.new(:static_metrics, :callback, keyword_init: true)

    CONTEXT_NAMESPACE = :graphql_metrics_analysis
    ANALYZER_INSTANCE_KEY = :analyzer_instance

    TIMINGS_CAPTURE_ENABLED = :timings_capture_enabled
    QUERY_START_TIME = :query_start_time
    QUERY_START_TIME_MONOTONIC = :query_start_time_monotonic
    PARSING_START_TIME_OFFSET = :parsing_start_time_offset
    PARSING_DURATION = :parsing_duration
    VALIDATION_START_TIME_OFFSET = :validation_start_time_offset
    VALIDATION_DURATION = :validation_duration

    cattr_accessor :pre_context
    # TODO: Not thread safe. Use Concurrent::ThreadLocalVar instead?

    INLINE_FIELD_TIMINGS = :inline_field_timings
    LAZY_FIELD_TIMINGS = :lazy_field_timings

    FIELD_TIMING_CALLBACKS_KEY = :field_timing_callbacks

    # NOTE: These constants come from the graphql ruby gem.
    GRAPHQL_GEM_LEXING_KEY = 'lex'
    GRAPHQL_GEM_PARSING_KEY = 'parse'
    GRAPHQL_GEM_VALIDATION_KEYS = ['validate', 'analyze_query', 'analyze_multiplex']
    GRAPHQL_GEM_TRACING_FIELD_KEY = 'execute_field'
    GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'
    GRAPHQL_GEM_TRACING_FIELD_KEYS = [GRAPHQL_GEM_TRACING_FIELD_KEY, GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY]

    class << self
      def current_time
        Process.clock_gettime(Process::CLOCK_REALTIME)
      end

      def current_time_monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def before_query(query)
        return if query.context[:skip_graphql_metrics_analysis]
        return unless query.valid?

        query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          ns[TIMINGS_CAPTURE_ENABLED] = true
          ns[INLINE_FIELD_TIMINGS] = {}
          ns[LAZY_FIELD_TIMINGS] = {}

          ns[FIELD_TIMING_CALLBACKS_KEY] = []
        end
      end

      # TODO: Split Analyzer up into several, dedicated classes.

      def after_query(query)
        return if query.context[:skip_graphql_metrics_analysis]
        return unless query.valid?

        query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          query_duration = current_time_monotonic - ns[QUERY_START_TIME_MONOTONIC]
          query_end_time = current_time

          runtime_query_metrics = {
            query_start_time: ns[QUERY_START_TIME],
            query_end_time: query_end_time,
            query_duration: query_duration,
            parsing_start_time_offset: ns[PARSING_START_TIME_OFFSET],
            parsing_duration: ns[PARSING_DURATION],
            validation_start_time_offset: ns[VALIDATION_START_TIME_OFFSET],
            validation_duration: ns[VALIDATION_DURATION],
          }

          analyzer = ns[ANALYZER_INSTANCE_KEY]
          analyzer.extract_query(runtime_query_metrics: runtime_query_metrics, context: query.context)
          analyzer.run_field_timing_callbacks
        end
      end

      def trace(key, data, &resolver_block)
        skip_tracing = data[:query]&.context&.fetch(:skip_graphql_metrics_analysis, false)
        return resolver_block.call if skip_tracing

        return setup_tracing_before_lexing(resolver_block) if key == GRAPHQL_GEM_LEXING_KEY
        return capture_parsing_time(resolver_block) if key == GRAPHQL_GEM_PARSING_KEY

        if GRAPHQL_GEM_VALIDATION_KEYS.include?(key)
          context = data[:query]&.context || data[:multiplex].queries.first.context
          return capture_validation_time(context, resolver_block)
        end

        return resolver_block.call unless GRAPHQL_GEM_TRACING_FIELD_KEYS.include?(key)

        Analyzer.pre_context = nil # cattr values no longer needed, everything we need is in context by now.

        context_key = case key
        when GRAPHQL_GEM_TRACING_FIELD_KEY
          INLINE_FIELD_TIMINGS
        when GRAPHQL_GEM_TRACING_LAZY_FIELD_KEY
          LAZY_FIELD_TIMINGS
        end

        if timings_capture_enabled?(data[:query].context)
          trace_field(context_key, data, resolver_block)
        else
          resolver_block.call
        end

      rescue => e
        binding.pry
        puts
      end

      def trace_field(context_key, data, resolver_block)
        path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }

        query_start_time_monotonic = data[:query].context.namespace(CONTEXT_NAMESPACE)[QUERY_START_TIME_MONOTONIC]

        field_start_time_monotonic = current_time_monotonic
        field_start_time_offset = field_start_time_monotonic - query_start_time_monotonic

        result = resolver_block.call
        duration = current_time_monotonic - field_start_time_monotonic

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

      def setup_tracing_before_lexing(resolver_block)
        # NOTE: `before_query` and `initialize` run after trace w/ `lex` key
        # It seems the only alternative to starting query timing here would be to ask users to pass wall / monotonic
        # clock times in their query context. Seems like a worse experience than us just assuming query start times
        # begin in lexing phase.

        # See http://ruby-concurrency.github.io/concurrent-ruby/master/Concurrent/ThreadLocalVar.html
        # Using this to overcome issue of using cattr.
        Analyzer.pre_context = Concurrent::ThreadLocalVar.new(OpenStruct.new)
        Analyzer.pre_context.value.query_start_time = current_time
        Analyzer.pre_context.value.query_start_time_monotonic = current_time_monotonic

        resolver_block.call
      rescue => e
        binding.pry
        puts
      end

      def capture_parsing_time(resolver_block)
        # NOTE: Need to store timings on class attributes, since there's no query context available during parsing.

        parsing_start_time_monotonic = current_time_monotonic

        Analyzer.pre_context.value.parsing_start_time_offset =
          parsing_start_time_monotonic - Analyzer.pre_context.value.query_start_time_monotonic

        result = resolver_block.call
        Analyzer.pre_context.value.parsing_duration = current_time_monotonic - parsing_start_time_monotonic

        result
      end

      def capture_validation_time(context, resolver_block)
        # NOTE: Now that we have a context available, move values out of the cattr into context and clear those values.

        validation_start_time_monotonic = current_time_monotonic

        validation_start_time_offset =
          validation_start_time_monotonic - Analyzer.pre_context.value.query_start_time_monotonic

        result = resolver_block.call

        validation_duration = current_time_monotonic - validation_start_time_monotonic

        context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          previous_validation_duration = ns[VALIDATION_DURATION] || 0

          ns[QUERY_START_TIME] = Analyzer.pre_context.value.query_start_time
          ns[QUERY_START_TIME_MONOTONIC] = Analyzer.pre_context.value.query_start_time_monotonic
          ns[PARSING_START_TIME_OFFSET] = Analyzer.pre_context.value.parsing_start_time_offset
          ns[PARSING_DURATION] = Analyzer.pre_context.value.parsing_duration
          ns[VALIDATION_START_TIME_OFFSET] = validation_start_time_offset

          # NOTE: We add up times spent validating the query syntax as well as running all analyzers
          ns[VALIDATION_DURATION] = validation_duration + previous_validation_duration
        end

        result
      rescue => e
        binding.pry
        puts
      end

      def timings_capture_enabled?(context)
        return false unless context
        !!context.namespace(CONTEXT_NAMESPACE)[TIMINGS_CAPTURE_ENABLED]
      rescue => e
        binding.pry
        puts
      end
    end

    def initialize(query_or_multiplex)
      super

      query_or_multiplex.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
        ns[ANALYZER_INSTANCE_KEY] = self
      end

      @query = query_or_multiplex
      @static_query_metrics = nil
      @field_timing_callbacks = []
    end

    def analyze?
      query.valid? && query.context[:skip_graphql_metrics_analysis] != true
    end

    def extract_query(runtime_query_metrics: {}, context:)
      query_extracted(@static_query_metrics.merge(runtime_query_metrics))
    end

    # TODO: Apollo Tracing spec https://docs.google.com/document/d/1B0dR09CcN_M4yqezkJ7VFPI-mKgQIVCt9PiUcIMEVNI/edit
    # Do so after integrating with Shopify/shopify, since we'll need another Instrumentation class to dig out values
    # left in memory by Analyzer.

    def on_enter_operation_definition(_node, _parent, visitor)
      @static_query_metrics = {
        operation_type: visitor.query.selected_operation.operation_type,
        operation_name: visitor.query.selected_operation.name,
      }
    end

    def on_leave_field(node, _parent, visitor)
      static_metrics = {
        field_name: node.name,
        return_type_name: visitor.type_definition.name,
        parent_type_name: visitor.parent_type_definition.name,
        deprecated: visitor.field_definition.deprecation_reason.present?,
        path: visitor.response_path,
      }

      if self.class.timings_capture_enabled?(visitor.query.context)
        callback = -> (metrics) {
          visitor.query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
            resolver_timings = ns[INLINE_FIELD_TIMINGS][metrics[:path]]
            lazy_field_timing = ns[LAZY_FIELD_TIMINGS][metrics[:path]]

            metrics = metrics.merge(
              resolver_timings: resolver_timings,
              lazy_resolver_timings: lazy_field_timing,
            )

            field_extracted(metrics)
          end
        }

        @field_timing_callbacks << FieldTimingCallback.new(static_metrics: static_metrics, callback: callback)
      else
        field_extracted(static_metrics)
      end
    end

    def run_field_timing_callbacks
      @field_timing_callbacks.each do |field_timing_callback|
        field_timing_callback.callback.call(field_timing_callback.static_metrics)
      end
    end

    # TODO: This is not called when argument is an input object field, provided by variables
    # See https://github.com/rmosolgo/graphql-ruby/pull/2574/files#diff-c845a0b55ef57645aa53df4e3836bc96R281
    def on_leave_argument(node, parent, visitor)
      argument_values = visitor.arguments_for(parent, visitor.field_definition).argument_values
      value = argument_values[node.name]

      # TODO: value cannot be easily obtained if the argument is a nested input object field.
      # See https://github.com/rmosolgo/graphql-ruby/issues/2573#issuecomment-548418296
      value_metrics = if value
        { value_is_null: value.value.nil?, value: value, default_used: value.default_used? }
      else
        { value_is_null: 'FIXME', value: 'FIXME', default_used: 'FIXME' }
      end

      static_metrics = {
        argument_name: node.name,
        argument_type_name: visitor.argument_definition.type.unwrap.to_s,
        parent_field_name: visitor.field_definition.name,
        parent_field_type_name: visitor.parent_type_definition.name,
      }

      argument_extracted(static_metrics.merge(value_metrics))
    end

    def result
      unless self.class.timings_capture_enabled?(@query.context)
        # If this class is not used as instrumentation and tracing, we still need to flush static query metrics
        # somewhere other than `after_query`.
        @query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          analyzer = ns[ANALYZER_INSTANCE_KEY]
          analyzer.extract_query(context: @query.context)
        end
      end
    end
  end
end
