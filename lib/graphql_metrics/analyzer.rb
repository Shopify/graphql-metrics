# frozen_string_literal: true

module GraphQLMetrics
  class Analyzer < GraphQL::Analysis::AST::Analyzer
    # TODO: Document execution order.

    def initialize(query_or_multiplex)
      super

      query_or_multiplex.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
        ns[ANALYZER_INSTANCE_KEY] = self
      end

      @query = query_or_multiplex
      @static_query_metrics = nil
      @static_field_metrics = []
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

      if GraphQLMetrics.timings_capture_enabled?(visitor.query.context)
        # NOTE: Emit these metrics later, once we have runtime metrics like field resolver timings.
        @static_field_metrics << static_metrics
      else
        field_extracted(static_metrics)
      end
    end

    def combine_and_log_static_and_runtime_field_metrics(context)
      @static_field_metrics.each do |static_metrics|
        context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          resolver_timings = ns[GraphQLMetrics::INLINE_FIELD_TIMINGS][static_metrics[:path]]
          lazy_field_timing = ns[GraphQLMetrics::LAZY_FIELD_TIMINGS][static_metrics[:path]]

          metrics = static_metrics.merge(
            resolver_timings: resolver_timings,
            lazy_resolver_timings: lazy_field_timing,
          )

          field_extracted(metrics)
        end
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
      unless GraphQLMetrics.timings_capture_enabled?(@query.context)
        # NOTE: If we're running as a static analyzer (i.e. not with instrumentation and tracing), we still need to
        # flush static query metrics somewhere other than `after_query`.
        @query.context.namespace(CONTEXT_NAMESPACE).tap do |ns|
          analyzer = ns[GraphQLMetrics::ANALYZER_INSTANCE_KEY]
          analyzer.extract_query(context: @query.context)
        end
      end
    end
  end
end
