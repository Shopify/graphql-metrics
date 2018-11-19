# frozen_string_literal: true

module GraphQLMetrics
  class Instrumentation
    extend Forwardable

    CONTEXT_NAMESPACE = :extracted_metrics
    TIMING_CACHE_KEY = :timing_cache
    START_TIME_KEY = :query_start_time

    attr_reader :ctx_namespace, :query
    def_delegators :extractor, :extractor_defines_any_visitors?

    def self.use(schema_definition)
      instrumentation = self.new
      return unless instrumentation.extractor_defines_any_visitors?

      instrumentation.setup_instrumentation(schema_definition)
    end

    def self.current_time
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def use(schema_definition)
      return unless extractor_defines_any_visitors?
      extractor.setup_instrumentation(schema_definition)
    end

    def setup_instrumentation(schema_definition)
      schema_definition.instrument(:query, self)
      schema_definition.instrument(:field, self)
    end

    def extractor
      @extractor ||= Extractor.new(self)
    end

    def before_query(query)
      return unless extractor_defines_any_visitors?

      ns = query.context.namespace(CONTEXT_NAMESPACE)
      ns[TIMING_CACHE_KEY] = {}
      ns[START_TIME_KEY] = self.class.current_time
    rescue StandardError => ex
      extractor.handle_extraction_exception(ex)
    end

    def after_query(query)
      @query = query

      return unless extractor_defines_any_visitors?
      return if respond_to?(:skip_extraction?) && skip_extraction?(query)
      return unless @ctx_namespace = query.context.namespace(CONTEXT_NAMESPACE)

      before_query_extracted(query, query.context) if respond_to?(:before_query_extracted)

      extractor.extract!(query)

      after_query_teardown(query) if respond_to?(:after_query_teardown)
    rescue StandardError => ex
      extractor.handle_extraction_exception(ex)
    end

    def instrument(type, field)
      return field unless respond_to?(:field_extracted) || extractor.respond_to?(:field_extracted)
      return field if type.introspection?

      old_resolve_proc = field.resolve_proc
      new_resolve_proc = ->(obj, args, ctx) do
        start_time = self.class.current_time
        result = old_resolve_proc.call(obj, args, ctx)

        begin
          next result if respond_to?(:skip_field_resolution_timing?) &&
            skip_field_resolution_timing?(query, ctx)

          end_time = self.class.current_time

          ns = ctx.namespace(CONTEXT_NAMESPACE)

          ns[TIMING_CACHE_KEY][ctx.ast_node] ||= []
          ns[TIMING_CACHE_KEY][ctx.ast_node] << end_time - start_time

          result
        rescue StandardError => ex
          extractor.handle_extraction_exception(ex)
          result
        end
      end

      field.redefine { resolve(new_resolve_proc) }
    end

    def after_query_resolver_times(ast_node)
      ctx_namespace.dig(Instrumentation::TIMING_CACHE_KEY).fetch(ast_node, [])
    end

    def after_query_start_and_end_time
      start_time = ctx_namespace[Instrumentation::START_TIME_KEY]
      return unless start_time

      [start_time, self.class.current_time]
    end
  end
end
