# frozen_string_literal: true

require "concurrent"
require "graphql_metrics/version"
require "graphql_metrics/instrumentation"
require "graphql_metrics/tracer"
require "graphql_metrics/analyzer"

# NOTE: Shared constants & utility methods
module GraphQLMetrics
  CONTEXT_NAMESPACE = :graphql_metrics_analysis
  ANALYZER_INSTANCE_KEY = :analyzer_instance
  TIMINGS_CAPTURE_ENABLED = :timings_capture_enabled
  SKIP_GRAPHQL_METRICS_ANALYSIS = :skip_graphql_metrics_analysis

  QUERY_START_TIME = :query_start_time
  QUERY_START_TIME_MONOTONIC = :query_start_time_monotonic
  PARSING_START_TIME_OFFSET = :parsing_start_time_offset
  PARSING_DURATION = :parsing_duration
  VALIDATION_START_TIME_OFFSET = :validation_start_time_offset
  VALIDATION_DURATION = :validation_duration
  INLINE_FIELD_TIMINGS = :inline_field_timings
  LAZY_FIELD_TIMINGS = :lazy_field_timings

  def self.timings_capture_enabled?(context)
    return false unless context
    !!context.namespace(CONTEXT_NAMESPACE)[TIMINGS_CAPTURE_ENABLED]
  end

  def self.current_time
    Process.clock_gettime(Process::CLOCK_REALTIME)
  end

  def self.current_time_monotonic
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
