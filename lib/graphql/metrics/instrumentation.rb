# typed: false
# frozen_string_literal: true

module GraphQL
  module Metrics
    class Instrumentation
      def before_query(query)
        unless query_present_and_valid?(query)
          # Setting this prevents Analyzer and Tracer from trying to gather runtime metrics for invalid queries.
          query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS] = true
        end

        # Even if queries are present and valid, applications may set this context value in order to opt out of
        # having Analyzer and Tracer gather runtime metrics.
        # If we're skipping runtime metrics, then both Instrumentation before_ and after_query can and should be
        # short-circuited as well.
        return if query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)
        ns[GraphQL::Metrics::TIMINGS_CAPTURE_ENABLED] = true
        ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS] = {}
        ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS] = {}
      end

      def after_query(query)
        return if query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        ns = query.context.namespace(CONTEXT_NAMESPACE)

        # NOTE: The start time stored at `ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]` is captured during query
        # parsing, which occurs before `Instrumentation#before_query`.
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
