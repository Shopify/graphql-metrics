# frozen_string_literal: true

require "concurrent"
require "graphql/metrics/version"
require "graphql/metrics/instrumentation"
require "graphql/metrics/trace"
require "graphql/metrics/analyzer"

module GraphQL
  module Metrics
    # The context namespace for all values stored by this gem.
    CONTEXT_NAMESPACE = :graphql_metrics_analysis

    # Skip metrics capture altogher, by setting `skip_graphql_metrics_analysis: true` in query context.
    SKIP_GRAPHQL_METRICS_ANALYSIS = :skip_graphql_metrics_analysis

    # Skips just field and argument logging, when query metrics logging is still desirable
    SKIP_FIELD_AND_ARGUMENT_METRICS = :skip_field_and_argument_metrics

    # Timings related constants.
    TIMINGS_CAPTURE_ENABLED = :timings_capture_enabled
    ANALYZER_INSTANCE_KEY = :analyzer_instance

    # Context keys to store timings for query phases of execution, field resolver timings.
    MULTIPLEX_START_TIME = :multiplex_start_time
    MULTIPLEX_START_TIME_MONOTONIC = :multiplex_start_time_monotonic
    QUERY_START_TIME = :query_start_time
    QUERY_START_TIME_MONOTONIC = :query_start_time_monotonic
    LEXING_DURATION = :lexing_duration
    PARSING_DURATION = :parsing_duration
    VALIDATION_DURATION = :validation_duration
    ANALYSIS_DURATION = :analysis_duration
    INLINE_FIELD_TIMINGS = :inline_field_timings
    LAZY_FIELD_TIMINGS = :lazy_field_timings

    def self.current_time
      Process.clock_gettime(Process::CLOCK_REALTIME)
    end

    def self.current_time_monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def self.time
      start_time = current_time_monotonic
      result = yield
      duration = current_time_monotonic - start_time
      [result, duration]
    end

    def self.use(
      schema_defn,
      analyzer_class:,
      tracer: GraphQL::Metrics::Trace,
      capture_timings: nil,
      capture_field_timings: nil,
      trace_mode: :default
    )
      if capture_field_timings && !capture_timings
        raise ArgumentError, "Cannot capture field timings without capturing query timings"
      end

      capture_timings = true if capture_timings.nil?
      capture_field_timings = true if capture_field_timings.nil?
      capture_field_timings = false if !capture_timings

      schema_defn.trace_with(GraphQL::Metrics::Instrumentation, capture_field_timings: capture_field_timings)
      schema_defn.trace_with(tracer, mode: trace_mode) if capture_timings
      schema_defn.query_analyzer(analyzer_class)
    end
  end
end
