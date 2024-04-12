# frozen_string_literal: true

module GraphQL
  module Metrics
    module Instrumentation
      def initialize(processor_class:, **options)
        query_or_multiplex = options[:query] || options[:multiplex]
        @processor = processor_class.new(query_or_multiplex)
        super
      end

      def execute_multiplex(multiplex:)
        return super if multiplex.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        result = nil

        multiplex.queries.each do |query|
          ns = query.context.namespace(CONTEXT_NAMESPACE)
          ns[GraphQL::Metrics::TIMINGS_CAPTURE_ENABLED] = true
          ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS] = Hash.new { |h, k| h[k] = [] }
          ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS] = Hash.new { |h, k| h[k] = [] }
        end

        begin
          result = super
        ensure
          multiplex.queries.each do |query|
            handle_query(query)
          end
        end

        result
      end

      private

      def handle_query(query)
        ns = query.context.namespace(CONTEXT_NAMESPACE)

        query_duration = GraphQL::Metrics.current_time_monotonic - ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]

        runtime_query_metrics = {
          query_start_time: ns[GraphQL::Metrics::QUERY_START_TIME],
          query_duration: query_duration,
          parsing_start_time_offset: ns[GraphQL::Metrics::PARSING_START_TIME_OFFSET],
          parsing_duration: ns[GraphQL::Metrics::PARSING_DURATION],
          validation_start_time_offset: ns[GraphQL::Metrics::VALIDATION_START_TIME_OFFSET],
          validation_duration: ns[GraphQL::Metrics::VALIDATION_DURATION],
          analysis_start_time_offset: ns[GraphQL::Metrics::ANALYSIS_START_TIME_OFFSET],
          analysis_duration: ns[GraphQL::Metrics::ANALYSIS_DURATION],
          multiplex_start_time: ns[GraphQL::Metrics::MULTIPLEX_START_TIME],
        }

        query_metrics = ns[:query_metrics].to_h.merge(runtime_query_metrics)
        @processor.query_extracted(query_metrics, query: query)

        ns[:field_metrics].each do |path, metric|
          metric[:resolver_timings] = ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS][path]
          metric[:lazy_resolver_timings] = ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS][path]

          @processor.field_extracted(metric, query: query)
        end

        ns[:argument_metrics].each do |metric|
          @processor.argument_extracted(metric, query: query)
        end

        ns[:directive_metrics].each do |metric|
          @processor.directive_extracted(metric, query: query)
        end
      end
    end
  end
end
