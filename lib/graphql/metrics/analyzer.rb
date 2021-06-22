# frozen_string_literal: true

module GraphQL
  module Metrics
    class Analyzer < GraphQL::Analysis::AST::Analyzer
      attr_reader :query
      DIRECTIVE_TYPE = "__Directive"

      def initialize(query_or_multiplex)
        super

        @query = query_or_multiplex
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        ns[ANALYZER_INSTANCE_KEY] = self

        @static_query_metrics = nil
        @static_field_metrics = []
      end

      def analyze?
        query.valid? && !query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]
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

      def on_leave_field(node, parent, visitor)
        return if visitor.field_definition.introspection?
        return if query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]

        argument_values = arguments_for(node, visitor.field_definition)
        extract_arguments(
          argument: argument_values,
          definition: visitor.field_definition,
          parent: parent
        ) if argument_values

        static_metrics = {
          field_name: node.name,
          return_type_name: visitor.type_definition.graphql_name,
          parent_type_name: visitor.parent_type_definition.graphql_name,
          deprecated: !visitor.field_definition.deprecation_reason.nil?,
          path: visitor.response_path,
        }

        if GraphQL::Metrics.timings_capture_enabled?(query.context)
          @static_field_metrics << static_metrics
        else
          field_extracted(static_metrics)
        end
      end

      def extract_fields(with_runtime_metrics: true)
        return if query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)

        @static_field_metrics.each do |static_metrics|

          if with_runtime_metrics
            resolver_timings = ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS][static_metrics[:path]]
            lazy_resolver_timings = ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS][static_metrics[:path]]

            static_metrics[:resolver_timings] = resolver_timings || []
            static_metrics[:lazy_resolver_timings] = lazy_resolver_timings || []
          end

          field_extracted(static_metrics)
        end
      end

      def on_enter_directive(node, parent, visitor)
        argument_values = arguments_for(node, visitor.directive_definition)
        extract_arguments(
          argument: argument_values,
          definition: visitor.directive_definition,
          parent: parent
        ) if argument_values

        directive_extracted({ directive_name: node.name })
      end

      def result
        return if GraphQL::Metrics.timings_capture_enabled?(query.context)
        return if query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        # NOTE: If we're running as a static analyzer (i.e. not with instrumentation and tracing), we still need to
        # flush static query metrics somewhere other than `after_query`.
        ns = query.context.namespace(CONTEXT_NAMESPACE)
        analyzer = ns[GraphQL::Metrics::ANALYZER_INSTANCE_KEY]
        analyzer.extract_query
      end

      private

      def arguments_for(node, definition)
        # Arguments can raise execution errors within their `prepare` methods
        # which aren't properly handled during analysis so we have to handle
        # them ourselves safely and return `nil`.
        query.arguments_for(node, definition)
      rescue ::GraphQL::ExecutionError
        nil
      end

      def extract_arguments(argument:, definition:, parent:, parent_input_object: nil)
        case argument
        when Array
          argument.each do |a|
            extract_arguments(
              argument: a,
              definition: definition,
              parent_input_object: parent_input_object,
              parent: parent
            )
          end
        when Hash
          argument.each_value do |a|
            extract_arguments(
              argument: a,
              definition: definition,
              parent_input_object: parent_input_object,
              parent: parent)
          end
        when ::GraphQL::Execution::Interpreter::Arguments
          argument.each_value do |arg_val|
            extract_arguments(
              argument: arg_val,
              definition: definition,
              parent_input_object: parent_input_object,
              parent: parent
          )
          end
        when ::GraphQL::Execution::Interpreter::ArgumentValue
          extract_argument(
            value: argument,
            definition: definition,
            parent_input_object: parent_input_object,
            parent: parent
          )
          extract_arguments(
            argument:argument.value,
            definition: definition,
            parent_input_object: parent_input_object,
            parent: parent
          )
        when ::GraphQL::Schema::InputObject
          input_object_argument_values = argument.arguments.argument_values.values
          parent_input_object = input_object_argument_values.first&.definition&.owner

          extract_arguments(
            argument: input_object_argument_values,
            definition: definition,
            parent_input_object: parent_input_object,
            parent: parent
          )
        end
      end

      def extract_argument(value:, definition:, parent_input_object:, parent:)
        parent_type_name = if definition.is_a?(GraphQL::Schema::Field)
          definition.owner.graphql_name
        else
          DIRECTIVE_TYPE
        end

        grand_parent_name = if parent.is_a?(GraphQL::Language::Nodes::OperationDefinition)
          parent.operation_type
        else
          parent.name
        end

        static_metrics = {
          argument_name: value.definition.graphql_name,
          argument_type_name: value.definition.type.unwrap.graphql_name,
          parent_name: definition.graphql_name,
          grandparent_type_name: parent_type_name,
          grandparent_node_name: grand_parent_name,
          parent_input_object_type: parent_input_object&.graphql_name,
          default_used: value.default_used?,
          value_is_null: value.value.nil?,
          value: value,
        }

        argument_extracted(static_metrics)
      end
    end
  end
end
