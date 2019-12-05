# frozen_string_literal: true

module GraphQL
  module Metrics
    class Instrumentation
      def before_query(query)
        unless query_present_and_valid?(query)
          query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS] = true
        end

        # NOTE: This context value may have been set to true in the application, so we should still return early here if
        # it's set, even if the query is valid.
        return if query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)
        ns[GraphQL::Metrics::TIMINGS_CAPTURE_ENABLED] = true
        ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS] = {}
        ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS] = {}
      end

      def after_query(query)
        return if query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)
        query_duration = GraphQL::Metrics.current_time_monotonic - ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]

        runtime_query_metrics = {
          query_start_time: ns[GraphQL::Metrics::QUERY_START_TIME],
          query_duration: query_duration,
          parsing_start_time_offset: ns[GraphQL::Metrics::PARSING_START_TIME_OFFSET],
          parsing_duration: ns[GraphQL::Metrics::PARSING_DURATION],
          validation_start_time_offset: ns[GraphQL::Metrics::VALIDATION_START_TIME_OFFSET],
          validation_duration: ns[GraphQL::Metrics::VALIDATION_DURATION],
        }

        analyzer = ns[GraphQL::Metrics::ANALYZER_INSTANCE_KEY]
        analyzer.extract_fields_with_runtime_metrics
        analyzer.extract_query(runtime_query_metrics: runtime_query_metrics)
      end

      private

      def query_present_and_valid?(query)
        query.valid? && query.document.to_query_string.present?
      end
    end
  end
end
