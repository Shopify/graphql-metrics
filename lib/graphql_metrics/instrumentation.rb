# frozen_string_literal: true

module GraphQLMetrics
  class Instrumentation
    def before_query(query)
      query_present_and_valid = query.valid? && query.document.to_query_string.present?

      unless query_present_and_valid
        query.context[GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS] = true
      end

      # NOTE: This context value may have been set to true in the application, so we should still return early here if
      # it's set, even if the query is valid.
      return if query.context[GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

      ns = query.context.namespace(CONTEXT_NAMESPACE)
      ns[GraphQLMetrics::TIMINGS_CAPTURE_ENABLED] = true
      ns[GraphQLMetrics::INLINE_FIELD_TIMINGS] = {}
      ns[GraphQLMetrics::LAZY_FIELD_TIMINGS] = {}
    end

    def after_query(query)
      return if query.context[GraphQLMetrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

      ns = query.context.namespace(CONTEXT_NAMESPACE)
      query_duration = GraphQLMetrics.current_time_monotonic - ns[GraphQLMetrics::QUERY_START_TIME_MONOTONIC]

      runtime_query_metrics = {
        query_start_time: ns[GraphQLMetrics::QUERY_START_TIME],
        query_duration: query_duration,
        parsing_start_time_offset: ns[GraphQLMetrics::PARSING_START_TIME_OFFSET],
        parsing_duration: ns[GraphQLMetrics::PARSING_DURATION],
        validation_start_time_offset: ns[GraphQLMetrics::VALIDATION_START_TIME_OFFSET],
        validation_duration: ns[GraphQLMetrics::VALIDATION_DURATION],
      }

      analyzer = ns[GraphQLMetrics::ANALYZER_INSTANCE_KEY]
      analyzer.extract_query(runtime_query_metrics: runtime_query_metrics)
      analyzer.extract_fields_with_runtime_metrics
    end
  end
end
