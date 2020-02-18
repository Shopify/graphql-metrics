# frozen_string_literal: true

module GraphQL
  module Metrics
    class Analyzer < GraphQL::Analysis::AST::Analyzer
      attr_reader :query

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

      def on_leave_field(node, _parent, visitor)
        return if visitor.field_definition.introspection?
        return if query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]

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

        if GraphQL::Metrics.timings_capture_enabled?(query.context)
          @static_field_metrics << static_metrics
        else
          field_extracted(static_metrics)
        end
      end

      def extract_fields_with_runtime_metrics
        return if query.context[SKIP_FIELD_AND_ARGUMENT_METRICS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)

        @static_field_metrics.each do |static_metrics|
          resolver_timings = ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS][static_metrics[:path]]
          lazy_field_timings = ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS][static_metrics[:path]]

          metrics = static_metrics.merge(
            resolver_timings: resolver_timings || [],
            lazy_resolver_timings: lazy_field_timings || [],
          )

          field_extracted(metrics)
        end
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

      def extract_arguments(argument, field_defn, parent_input_object = nil)
        case argument
        when Array
          argument.each do |a|
            extract_arguments(a, field_defn, parent_input_object)
          end
        when Hash
          argument.each_value do |a|
            extract_arguments(a, field_defn, parent_input_object)
          end
        when ::GraphQL::Query::Arguments
          argument.each_value do |arg_val|
            extract_arguments(arg_val, field_defn, parent_input_object)
          end
        when ::GraphQL::Query::Arguments::ArgumentValue
          extract_enum_value(argument, field_defn)
          extract_argument(argument, field_defn, parent_input_object)
          extract_arguments(argument.value, field_defn, parent_input_object)
        when ::GraphQL::Schema::InputObject
          input_object_argument_values = argument.arguments.argument_values.values
          parent_input_object = input_object_argument_values.first&.definition&.metadata&.fetch(:type_class, nil)&.owner

          extract_arguments(input_object_argument_values, field_defn, parent_input_object)
        end
      # rescue => e
      #   binding.pry
      #   puts
      end

      def extract_argument(value, field_defn, parent_input_object = nil)
        static_metrics = {
          argument_name: value.definition.expose_as,
          argument_type_name: value.definition.type.unwrap.to_s,
          parent_field_name: field_defn.name,
          parent_field_type_name: field_defn.metadata[:type_class].owner.graphql_name,
          parent_input_object_type: parent_input_object&.graphql_name,
          default_used: value.default_used?,
          value_is_null: value.value.nil?,
          value: value,
        }

        argument_extracted(static_metrics)
      # rescue => e
      #   binding.pry
      #   puts
      end

      def extract_enum_value(value, field_defn)
        return unless (unwrapped_type = value.definition.type.unwrap)
        return unless unwrapped_type.is_a?(GraphQL::EnumType)

        enum_value = value.value
        value_definition = unwrapped_type.values[enum_value]

        binding.pry if value_definition.nil?

        static_metrics = {
          argument_name: value.definition.expose_as,
          argument_type_name: unwrapped_type.to_s,
          default_used: value.default_used?,
          deprecated: value_definition.deprecation_reason.present?,
          value: enum_value,
        }

        enum_value_extracted(static_metrics)
      # rescue => e
      #   binding.pry
      #   puts
      end
    end
  end
end
