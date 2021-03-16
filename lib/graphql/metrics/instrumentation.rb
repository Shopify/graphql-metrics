# frozen_string_literal: true

module GraphQL
  module Metrics
    class Instrumentation
      def before_query(query)
        unless query_present_and_valid?(query)
          # Setting this prevents Analyzer and Tracer from trying to gather runtime metrics for invalid queries.
          query.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS] = true
        end

        puts '* Instrumentation.before_query'

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
        analyzer = ns[GraphQL::Metrics::ANALYZER_INSTANCE_KEY]

        if runtime_metrics_interrupted?(ns)
          # If runtime metrics were interrupted, then it's most likely that the application raised an exception and that
          # query parsing (which is instrumented by GraphQL::Metrics::Tracer) was abruptly stopped.
          #
          # In this scenario, we still attempt to log whatever static query metrics we've collected, with runtime
          # metrics (like query, field resolver timings) excluded.
          analyzer.extract_fields(with_runtime_metrics: false)
          analyzer.extract_query
        else
          query_duration = GraphQL::Metrics.current_time_monotonic - ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]

          puts '* Instrumentation.after_query - query_duration extracted for current query'

          runtime_query_metrics = {
            query_start_time: ns[GraphQL::Metrics::QUERY_START_TIME],
            query_duration: query_duration,
            parsing_start_time_offset: ns[GraphQL::Metrics::PARSING_START_TIME_OFFSET],
            parsing_duration: ns[GraphQL::Metrics::PARSING_DURATION],
            validation_start_time_offset: ns[GraphQL::Metrics::VALIDATION_START_TIME_OFFSET],
            validation_duration: ns[GraphQL::Metrics::VALIDATION_DURATION],
            lexing_start_time_offset: ns[GraphQL::Metrics::LEXING_START_TIME_OFFSET],
            lexing_duration: ns[GraphQL::Metrics::LEXING_DURATION],
            analysis_start_time_offset: ns[GraphQL::Metrics::ANALYSIS_START_TIME_OFFSET],
            analysis_duration: ns[GraphQL::Metrics::ANALYSIS_DURATION],
            multiplex_start_time: ns[GraphQL::Metrics::MULTIPLEX_START_TIME],
          }

          analyzer.extract_fields
          analyzer.extract_query(runtime_query_metrics: runtime_query_metrics)
        end
      end

      private

      def query_present_and_valid?(query)
        # Check for selected_operation as well for graphql 1.9 compatibility
        # which did not reject "empty" documents in its parser.
        query.valid? && !query.selected_operation.nil?
      end

      def runtime_metrics_interrupted?(context_namespace)
        # NOTE: The start time stored at `ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]` is captured during query
        # parsing, which occurs before `Instrumentation#before_query`.
        context_namespace.key?(GraphQL::Metrics::QUERY_START_TIME_MONOTONIC) == false
      end
    end
  end
end
