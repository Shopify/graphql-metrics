# frozen_string_literal: true

module GraphQLMetrics
  class Extractor
    CONTEXT_NAMESPACE = :extracted_metrics
    TIMING_CACHE_KEY = :timing_cache
    START_TIME_KEY = :query_start_time

    EXPLICIT_NULL = 'EXPLICIT_NULL'
    IMPLICIT_NULL = 'IMPLICIT_NULL'
    NON_NULL = 'NON_NULL'

    attr_reader :query, :ctx_namespace

    def self.use(schema_definition)
      extractor = self.new
      return unless extractor.extractor_defines_any_visitors?

      extractor.setup_instrumentation(schema_definition)
    end

    def use(schema_definition)
      return unless extractor_defines_any_visitors?
      setup_instrumentation(schema_definition)
    end

    def setup_instrumentation(schema_definition)
      schema_definition.instrument(:query, self)
      schema_definition.instrument(:field, self)
    end

    def before_query(query)
      return unless extractor_defines_any_visitors?

      ns = query.context.namespace(CONTEXT_NAMESPACE)
      ns[TIMING_CACHE_KEY] = {}
      ns[START_TIME_KEY] = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def after_query(query)
      return unless extractor_defines_any_visitors?

      @query = query
      return unless query.valid?
      return if respond_to?(:skip_extraction?) && skip_extraction?(query)
      return unless @ctx_namespace = query.context.namespace(CONTEXT_NAMESPACE)
      return unless query.irep_selection

      before_query_extracted(query, query.context) if respond_to?(:before_query_extracted)
      extract_query

      query.operations.each_value do |operation|
        extract_variables(operation)
      end

      extract_node(query.irep_selection)
      extract_batch_loaders

      after_query_teardown(query) if respond_to?(:after_query_teardown)
    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def instrument(type, field)
      return field unless respond_to?(:field_extracted)
      return field if type.introspection?

      old_resolve_proc = field.resolve_proc
      new_resolve_proc = ->(obj, args, ctx) do
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = old_resolve_proc.call(obj, args, ctx)

        begin
          next result if respond_to?(:skip_field_resolution_timing?) &&
            skip_field_resolution_timing?(query, ctx)

          end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

          ns = ctx.namespace(CONTEXT_NAMESPACE)

          ns[TIMING_CACHE_KEY][ctx.ast_node] ||= []
          ns[TIMING_CACHE_KEY][ctx.ast_node] << end_time - start_time

          result
        rescue StandardError => ex
          handle_extraction_exception(ex)
          result
        end
      end

      field.redefine { resolve(new_resolve_proc) }
    end

    def extractor_defines_any_visitors?
      respond_to?(:query_extracted) ||
        respond_to?(:field_extracted) ||
        respond_to?(:argument_extracted) ||
        respond_to?(:variable_extracted) ||
        respond_to?(:batch_loaded_field_extracted) ||
        respond_to?(:before_query_extracted)
    end

    def handle_extraction_exception(ex)
      raise ex
    end

    def extract_batch_loaders
      return unless respond_to?(:batch_loaded_field_extracted)

      TimedBatchExecutor.timings.each do |key, resolve_meta|
        key, identifiers = TimedBatchExecutor.serialize_loader_key(key)

        batch_loaded_field_extracted(
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
      return unless respond_to?(:query_extracted)

      start_time = ctx_namespace[START_TIME_KEY]
      return unless start_time

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      query_extracted(
        {
          query_string: query.document.to_query_string,
          operation_type: query.selected_operation.operation_type,
          operation_name: query.selected_operation_name,
          duration: end_time - start_time
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
      return unless respond_to?(:field_extracted)
      return unless irep_node.definition

      field_extracted(
        {
          type_name: irep_node.owner_type.name,
          field_name: irep_node.definition.name,
          deprecated: irep_node.definition.deprecation_reason.present?,
          resolver_times: ctx_namespace.dig(TIMING_CACHE_KEY, irep_node.ast_node) || [],
        },
        {
          irep_node: irep_node,
          query: query,
          ctx_namespace: ctx_namespace
        }
      )

    rescue StandardError => ex
      handle_extraction_exception(ex)
    end

    def extract_argument(value, irep_node, types)
      return unless respond_to?(:argument_extracted)

      argument_extracted(
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

    def extract_variables(operation)
      return unless respond_to?(:variable_extracted)

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

        variable_extracted(
          {
            operation_name: operation.name,
            unwrapped_type_name: unwrapped_type(variable.type),
            type: variable.type.to_query_string,
            default_value_type: default_value_type,
            provided_value: value_provided,
            default_used: default_used
          },
          {
            query: query
          }
        )
      end
    rescue StandardError => ex
      handle_extraction_exception(ex)
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
  end
end
