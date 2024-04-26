# frozen_string_literal: true

module GraphQL
  module Metrics
    class Analyzer < GraphQL::Analysis::AST::Analyzer
      DIRECTIVE_TYPE = "__Directive"
      private_constant :DIRECTIVE_TYPE

      def initialize(query_or_multiplex)
        super

        @query = query_or_multiplex
        @ns = query.context.namespace(CONTEXT_NAMESPACE)

        @query_metrics = nil
        @field_metrics = {}
        @argument_metrics = []
        @directive_metrics = []
      end

      def analyze?
        query.valid? && !query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]
      end

      def result
        @ns[:query_metrics] = @query_metrics
        @ns[:field_metrics] = @field_metrics
        @ns[:argument_metrics] = @argument_metrics
        @ns[:directive_metrics] = @directive_metrics
      end

      def on_enter_operation_definition(_node, _parent, visitor)
        @query_metrics = {
          operation_type: visitor.query.selected_operation.operation_type,
          operation_name: visitor.query.selected_operation.name,
        }
      end

      def on_leave_field(node, parent, visitor)
        return if query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]

        field_defn = visitor.field_definition
        return if field_defn.introspection?

        argument_values = arguments_for(node, field_defn)

        extract_arguments(
          argument: argument_values,
          definition: field_defn,
          parent: parent
        ) if argument_values

        return if @field_metrics.key?(field_defn.path)

        @field_metrics[field_defn.path] = {
          field_name: node.name,
          return_type_name: visitor.type_definition.graphql_name,
          parent_type_name: visitor.parent_type_definition.graphql_name,
          deprecated: !field_defn.deprecation_reason.nil?,
        }
      end

      def on_enter_directive(node, parent, visitor)
        argument_values = arguments_for(node, visitor.directive_definition)

        extract_arguments(
          argument: argument_values,
          definition: visitor.directive_definition,
          parent: parent
        ) if argument_values

        @directive_metrics << { directive_name: node.name }
      end

      private

      attr_reader :query

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

        grand_parent_name = case parent
        when GraphQL::Language::Nodes::OperationDefinition
          parent.operation_type
        when GraphQL::Language::Nodes::InlineFragment
          parent&.type&.name
        else
          parent.name
        end

        @argument_metrics << {
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
      end
    end
  end
end
