module GraphQLMetrics
  class Analyzer < GraphQL::Analysis::AST::Analyzer
    FieldTimingCallback = Struct.new(:static_metrics, :callback, keyword_init: true)

    CONTEXT_NAMESPACE = :graphql_metrics_analysis
    RUNTIME_METRICS_ENABLED = :runtime_metrics_enabled

    QUERY_START_TIME_KEY = :query_start_time
    QUERY_START_TIME_MONOTONIC_KEY = :query_start_time_monotonic
    FIELD_TIMING_CALLBACKS_KEY = :field_timing_callbacks
    ANALYZER_INSTANCE_KEY = :analyzer_instance

    # NOTE: These constants are used both to match tracing keys from graphql-ruby as well as to store in-line and lazy
    # field resolution timings in context.
    GRAPHQL_TRACING_FIELD_KEY = 'execute_field'
    GRAPHQL_TRACING_LAZY_FIELD_KEY = 'execute_field_lazy'

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
          ns[RUNTIME_METRICS_ENABLED] = true
          ns[FIELD_TIMING_CALLBACKS_KEY] = []
          ns[QUERY_START_TIME_KEY] = current_time
          ns[QUERY_START_TIME_MONOTONIC_KEY] = current_time_monotonic
          ns[GRAPHQL_TRACING_FIELD_KEY] = {}
          ns[GRAPHQL_TRACING_LAZY_FIELD_KEY] = {}
        end
      end

      def after_query(query)
        return if query.context[:skip_graphql_metrics_analysis]
        return unless query.valid?

        query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          duration = current_time_monotonic - ns[QUERY_START_TIME_MONOTONIC_KEY]
          runtime_metrics = { start_time: ns[QUERY_START_TIME_KEY], duration: duration }

          analyzer = ns[ANALYZER_INSTANCE_KEY]
          analyzer.extract_query(runtime_metrics: runtime_metrics, context: query.context)
          analyzer.run_field_timing_callbacks
        end
      end

      def trace(key, data, &block)
        skip_tracing = data[:query]&.context&.fetch(:skip_graphql_metrics_analysis, false)
        return block.call if skip_tracing || ![GRAPHQL_TRACING_FIELD_KEY, GRAPHQL_TRACING_LAZY_FIELD_KEY].include?(key)
        # NOTE: We can't just check `runtime_metrics_enabled?` here, since .trace runs before `before_query`, i.e.
        # during lexing, parsing, validation etc., and `before_query` doesn't run until `execute_multiplex`.

        if runtime_metrics_enabled?(data[:query]&.context)
          trace_field(key, data, block, key)
        else
          block.call
        end
      end

      def trace_field(_key, data, block, context_key)
        path_excluding_numeric_indicies = data[:path].select { |p| p.is_a?(String) }

        start_time = current_time
        start_time_monotonic = current_time_monotonic

        result = block.call
        duration = current_time_monotonic - start_time_monotonic

        data[:query].context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          ns[context_key][path_excluding_numeric_indicies] ||= []
          ns[context_key][path_excluding_numeric_indicies] << { start_time: start_time, duration: duration }
        end

        result
      end

      def runtime_metrics_enabled?(context)
        return false unless context
        !!context.namespace(CONTEXT_NAMESPACE)[RUNTIME_METRICS_ENABLED]
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

    def extract_query(runtime_metrics: {}, context:)
      query_extracted(@static_query_metrics.merge(runtime_metrics))
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

      if self.class.runtime_metrics_enabled?(visitor.query.context)
        callback = -> (metrics) {
          visitor.query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
            resolver_timings = ns[GRAPHQL_TRACING_FIELD_KEY][metrics[:path]]
            lazy_field_timing = ns[GRAPHQL_TRACING_LAZY_FIELD_KEY][metrics[:path]]

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
      unless self.class.runtime_metrics_enabled?(@query.context)
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
