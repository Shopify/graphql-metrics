# frozen_string_literal: true

module GraphQLMetrics
  class Extractor
    class DummyInstrumentor
      def after_query_start_and_end_time
        [nil, nil]
      end

      def after_query_resolver_times(_ast_node)
        []
      end

      def ctx_namespace
        {}
      end
    end

    EXPLICIT_NULL = 'EXPLICIT_NULL'
    IMPLICIT_NULL = 'IMPLICIT_NULL'
    NON_NULL = 'NON_NULL'

    attr_reader :query

    def initialize(instrumentor = DummyInstrumentor.new)
      @instrumentor = instrumentor
    end

    def instrumentor
      @instrumentor ||= DummyInstrumentor.new
    end

    def extract!(query)
      @query = query

      return unless query.valid?
      return unless query.irep_selection

      extract_query

      used_variables = extract_used_variables

      query.operations.each_value do |operation|
        extract_variables(operation, used_variables)
      end

      extract_node(query.irep_selection)
      extract_batch_loaders
    end

    def extractor_defines_any_visitors?
      [self, instrumentor].any? do |extractor_definer|
        extractor_definer.respond_to?(:query_extracted) ||
        extractor_definer.respond_to?(:field_extracted) ||
        extractor_definer.respond_to?(:argument_extracted) ||
        extractor_definer.respond_to?(:variable_extracted) ||
        extractor_definer.respond_to?(:batch_loaded_field_extracted) ||
        extractor_definer.respond_to?(:before_query_extracted)
      end
    end

    def handle_extraction_exception(ex)
      raise ex
    end

    private

    def extract_batch_loaders
      return unless batch_loaded_field_extracted_method = extraction_method(:batch_loaded_field_extracted)

      TimedBatchExecutor.timings.each do |key, resolve_meta|
        key, identifiers = TimedBatchExecutor.serialize_loader_key(key)

        batch_loaded_field_extracted_method.call(
          {
            key: key,
            identifiers: identifiers,
            times: resolve_meta[:times],
            perform_queue_sizes: resolve_meta[:perform_queue_sizes],
          },
          {
            query: query,
          }
        )
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
    ensure
      TimedBatchExecutor.clear_timings
    end

    def extract_query
      return unless query_extracted_method = extraction_method(:query_extracted)

      start_time, end_time = instrumentor.after_query_start_and_end_time
      duration = start_time && end_time ? end_time - start_time : nil

      query_extracted_method.call(
        {
          operation_type: query.selected_operation.operation_type,
          operation_name: query.selected_operation_name,
          duration: duration
        },
        {
          query: query,
          start_time: start_time,
          end_time: end_time
        }
      )
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_field(irep_node)
      return unless field_extracted_method = extraction_method(:field_extracted)
      return unless irep_node.definition

      resolver_times = instrumentor.after_query_resolver_times(irep_node.ast_node)

      field_extracted_method.call(
        {
          type_name: irep_node.owner_type.name,
          field_name: irep_node.definition.name,
          deprecated: irep_node.definition.deprecation_reason.present?,
          resolver_times: resolver_times || [],
        },
        {
          irep_node: irep_node,
          query: query,
          ctx_namespace: instrumentor.ctx_namespace
        }
      )

    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_argument(value, irep_node, types)
      return unless argument_extracted_method = extraction_method(:argument_extracted)

      argument_extracted_method.call(
        {
          name: value.definition.expose_as,
          type: value.definition.type.unwrap.to_s,
          value_is_null: value.value.nil?,
          default_used: value.default_used?,
          parent_input_type: types.map(&:unwrap).last&.to_s,
          field_name: irep_node.definition.name,
          field_base_type: irep_node&.owner_type.to_s
        },
        {
          query: query,
          irep_node: irep_node,
          value: value,
        }
      )
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_variables(operation, used_variables)
      return unless variable_extracted_method = extraction_method(:variable_extracted)

      operation.variables.each do |variable|
        value_provided = query.provided_variables.key?(variable.name)

        default_value_type = case variable.default_value
        when GraphQL::Language::Nodes::NullValue
          EXPLICIT_NULL
        when nil
          IMPLICIT_NULL
        else
          NON_NULL
        end

        default_used = !value_provided && default_value_type != IMPLICIT_NULL

        variable_extracted_method.call(
          {
            operation_name: operation.name,
            unwrapped_type_name: unwrapped_type(variable.type),
            type: variable.type.to_query_string,
            default_value_type: default_value_type,
            provided_value: value_provided,
            default_used: default_used,
            used_in_operation: used_variables.include?(variable.name)
          },
          {
            query: query
          }
        )
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_used_variables
      query.irep_selection.ast_node.variables.each_with_object(Set.new) { |v, set| set << v.name }
    end

    def extract_arguments(irep_node)
      return unless irep_node.ast_node.is_a?(GraphQL::Language::Nodes::Field)

      traverse_arguments(irep_node.arguments.argument_values.values, irep_node)
    rescue GraphQL::ExecutionError
      # no-op. See https://github.com/rmosolgo/graphql-ruby/issues/982.
      nil
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_node(irep_node)
      extract_field(irep_node)
      extract_arguments(irep_node)

      irep_node.scoped_children.each_value do |children|
        children.each_value do |child_irep_node|
          extract_node(child_irep_node)
        end
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def traverse_arguments(value, irep_node, types = [])
      case value
      when Array
        value.each do |v|
          traverse_arguments(v, irep_node, types)
        end
      when Hash
        value.each_value do |v|
          traverse_arguments(v, irep_node, types)
        end
      when ::GraphQL::Query::Arguments
        value.each_value do |arg_val|
          traverse_arguments(arg_val, irep_node, types)
        end
      when ::GraphQL::Query::Arguments::ArgumentValue
        extract_argument(value, irep_node, types)
        traverse_arguments(value.value, irep_node, types + [value.definition.type])
      when ::GraphQL::Schema::InputObject
        traverse_arguments(value.arguments.argument_values.values, irep_node, types)
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def unwrapped_type(type)
      if type.is_a?(GraphQL::Language::Nodes::WrapperType)
        unwrapped_type(type.of_type)
      else
        type.name
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extraction_method(method_name)
      @extraction_method_cache ||= {}
      return @extraction_method_cache[method_name] if @extraction_method_cache.has_key?(method_name)

      method = if respond_to?(method_name)
        method(method_name)
      elsif instrumentor && instrumentor.respond_to?(method_name)
        instrumentor.method(method_name)
      else
        nil
      end

      method.tap do |method|
        @extraction_method_cache[method_name] = method
      end
    end
  end
end
