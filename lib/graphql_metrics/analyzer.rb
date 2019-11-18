# frozen_string_literal: true

# Execution order:
# When used as instrumentation, an analyzer and tracing, the order of execution is:
#
# * Tracer.setup_tracing_before_lexing
# * Tracer.capture_parsing_time
# * Instrumentation.before_query (context setup)
# * Tracer.capture_validation_time (twice, once for `analyze_query`, then `analyze_multiplex`)
# * Analyzer#initialize (bit more context setup, instance vars setup)
# * Analyzer#result
# * Tracer.trace_field (n times)
# * Instrumentation.after_query (call query and field callbacks, now that we have all static and runtime metrics
#   gathered)
# * Analyzer#extract_query
# * Analyzer#query_extracted
# * Analyzer#extract_fields_with_runtime_metrics
#   * calls Analyzer#field_extracted n times
#
# When used as a simple analyzer, which doesn't gather or emit any runtime metrics (timings, arg values):
# * Analyzer#initialize
# * Analyzer#field_extracted n times
# * Analyzer#result
# * Analyzer#extract_query
# * Analyzer#query_extracted

module GraphQLMetrics
  class Analyzer < GraphQL::Analysis::AST::Analyzer
    attr_reader :query

    def initialize(query_or_multiplex)
      super

      # TODO: Handle multiplex of multiple queries
      # https://graphql-ruby.org/queries/multiplex.html
      @query = query_or_multiplex
      ns = query.context.namespace(CONTEXT_NAMESPACE)
      ns[ANALYZER_INSTANCE_KEY] = self

      @static_query_metrics = nil
      @static_field_metrics = []
    end

    def analyze?
      query.valid? && !query.context[GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS]
    end

    def extract_query(runtime_query_metrics: {})
      query_extracted(@static_query_metrics.merge(runtime_query_metrics)) if @static_query_metrics
    end

    def on_enter_operation_definition(_node, _parent, visitor)
      @static_query_metrics = {
        operation_type: visitor.query.selected_operation.operation_type,
        operation_name: visitor.query.selected_operation.name,
      }
    end

    def on_leave_field(node, _parent, visitor)
      # NOTE: @rmosolgo "I think it could be reduced to `arguments = visitor.arguments_for(ast_node)`"
      arguments = visitor.arguments_for(node, visitor.field_definition)
      extract_arguments(arguments.argument_values.values, visitor.field_definition)

      static_metrics = {
        field_name: node.name,
        return_type_name: visitor.type_definition.name,
        parent_type_name: visitor.parent_type_definition.name,
        deprecated: visitor.field_definition.deprecation_reason.present?,
        path: visitor.response_path,
      }

      if GraphQLMetrics.timings_capture_enabled?(query.context)
        @static_field_metrics << static_metrics
      else
        field_extracted(static_metrics)
      end
    end

    def extract_fields_with_runtime_metrics
      ns = query.context.namespace(CONTEXT_NAMESPACE)

      @static_field_metrics.each do |static_metrics|
        resolver_timings = ns[GraphQLMetrics::INLINE_FIELD_TIMINGS][static_metrics[:path]]
        lazy_field_timing = ns[GraphQLMetrics::LAZY_FIELD_TIMINGS][static_metrics[:path]]

        metrics = static_metrics.merge(
          resolver_timings: resolver_timings,
          lazy_resolver_timings: lazy_field_timing,
        )

        field_extracted(metrics)
      end
    end

    def result
      return if GraphQLMetrics.timings_capture_enabled?(query.context)
      return if query.context[GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

      # NOTE: If we're running as a static analyzer (i.e. not with instrumentation and tracing), we still need to
      # flush static query metrics somewhere other than `after_query`.
      ns = query.context.namespace(CONTEXT_NAMESPACE)
      analyzer = ns[GraphQLMetrics::ANALYZER_INSTANCE_KEY]
      analyzer.extract_query
    end

    private

    def extract_arguments(argument, field_defn)
      case argument
      when Array
        argument.each do |a|
          extract_arguments(a, field_defn)
        end
      when Hash
        argument.each_value do |a|
          extract_arguments(a, field_defn)
        end
      when ::GraphQL::Query::Arguments
        argument.each_value do |arg_val|
          extract_arguments(arg_val, field_defn)
        end
      when ::GraphQL::Query::Arguments::ArgumentValue
        extract_argument(argument, field_defn)
        extract_arguments(argument.value, field_defn)
      when ::GraphQL::Schema::InputObject
        extract_arguments(argument.arguments.argument_values.values, field_defn)
      end
    end

    def extract_argument(value, field_defn)
      static_metrics = {
        argument_name: value.definition.expose_as,
        argument_type_name: value.definition.type.unwrap.to_s,
        parent_field_name: field_defn.name,
        parent_field_type_name: field_defn.metadata[:type_class].owner.graphql_name,
        default_used: value.default_used?,
        value_is_null: value.value.nil?,
        value: value,
      }

      argument_extracted(static_metrics)
    end
  end
end
