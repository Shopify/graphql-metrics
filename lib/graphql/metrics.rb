# frozen_string_literal: true

require "concurrent"
require "graphql/metrics/version"
require "graphql/metrics/instrumentation"
require "graphql/metrics/trace"
require "graphql/metrics/tracer"
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
    LEXING_START_TIME_OFFSET = :lexing_start_time_offset
    LEXING_DURATION = :lexing_duration
    PARSING_START_TIME_OFFSET = :parsing_start_time_offset
    PARSING_DURATION = :parsing_duration
    VALIDATION_START_TIME_OFFSET = :validation_start_time_offset
    VALIDATION_DURATION = :validation_duration
    ANALYSIS_START_TIME_OFFSET = :analysis_start_time_offset
    ANALYSIS_DURATION = :analysis_duration
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

    def self.time(offset_time = nil)
      start_time = current_time_monotonic
      result = yield
      duration = current_time_monotonic - start_time
      time_since_offset = start_time - offset_time if offset_time
      TimedResult.new(start_time, duration, time_since_offset, result)
    end

    class TimedResult
      # NOTE: `time_since_offset` is used to produce start times timed phases of execution (validation, field
      # resolution). These start times are relative to the executed operation's start time, which is captured at the
      # outset of document parsing.
      #
      # The times produced are intentionally similar to:
      # https://github.com/apollographql/apollo-tracing#response-format
      #
      # Taking a field resolver start offset example:
      #
      # <   start offset   >
      # |------------------|----------|--------->
      # OS (t=0)           FS (t=1)   FE (t=2)
      #
      # OS = Operation start time
      # FS = Field resolver start time
      # FE = Field resolver end time
      #
      attr_reader :result, :start_time, :duration, :time_since_offset

      def initialize(start_time, duration, time_since_offset, result)
        @start_time = start_time
        @duration = duration
        @time_since_offset = time_since_offset
        @result = result
      end
    end
  end
end
