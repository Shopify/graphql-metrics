# frozen_string_literal: true

module GraphQL
  module Metrics
    module Instrumentation
      def initialize(capture_field_timings: true, **_options)
        @capture_field_timings = capture_field_timings

        super
      end

      def execute_multiplex(multiplex:)
        return super if multiplex.context[GraphQL::Metrics::SKIP_GRAPHQL_METRICS_ANALYSIS]

        result = nil

        multiplex.queries.each do |query|
          ns = query.context.namespace(CONTEXT_NAMESPACE)
          ns[GraphQL::Metrics::TIMINGS_CAPTURE_ENABLED] = @capture_field_timings
          ns[GraphQL::Metrics::INLINE_FIELD_TIMINGS] = Hash.new { |h, k| h[k] = [] }
          ns[GraphQL::Metrics::LAZY_FIELD_TIMINGS] = Hash.new { |h, k| h[k] = [] }
        end

        begin
          result = super
        ensure
          multiplex.queries.each do |query|
            handle_query(query) if query.valid?
          end
        end

        result
      end

      private

      def handle_query(query)
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

          runtime_query_metrics = {
            query_start_time: ns[GraphQL::Metrics::QUERY_START_TIME],
            query_duration: query_duration,
            parsing_duration: ns[GraphQL::Metrics::PARSING_DURATION],
            validation_duration: ns[GraphQL::Metrics::VALIDATION_DURATION],
            lexing_duration: ns[GraphQL::Metrics::LEXING_DURATION],
            analysis_duration: ns[GraphQL::Metrics::ANALYSIS_DURATION],
          }

          analyzer.extract_fields(with_runtime_metrics: @capture_field_timings)
          analyzer.extract_query(runtime_query_metrics: runtime_query_metrics)
        end
      end

      private

      def runtime_metrics_interrupted?(context_namespace)
        # NOTE: The start time stored at `ns[GraphQL::Metrics::QUERY_START_TIME_MONOTONIC]` is captured during query
        # parsing, which occurs before `Instrumentation#before_query`.
        context_namespace.key?(GraphQL::Metrics::QUERY_START_TIME_MONOTONIC) == false
      end
    end
  end
end
