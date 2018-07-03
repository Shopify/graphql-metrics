# frozen_string_literal: true

module GraphQLMetrics
  BASE_CLASS = if defined?(GraphQL::Batch::Executor)
    GraphQL::Batch::Executor
  else
    class NoExecutor
      class << self
        def resolve(_loader)
          super
        end

        def around_promise_callbacks
          super
        end
      end
    end

    NoExecutor
  end

  class TimedBatchExecutor < BASE_CLASS
    TIMINGS = {}
    private_constant :TIMINGS

    class << self
      def timings
        TIMINGS
      end

      def clear_timings
        TIMINGS.clear
      end

      def serialize_loader_key(loader_key)
        identifiers = []

        serialized = loader_key.map do |group_arg|
          if [Class, Symbol, String].include?(group_arg.class)
            group_arg
          elsif group_arg.is_a?(Numeric)
            identifiers << group_arg
            '_'
          elsif group_arg.respond_to?(:id)
            identifiers << group_arg.id
            "#{group_arg.class}/_"
          else
            '?'
          end
        end

        [serialized.map(&:to_s).join('/'), identifiers.map(&:to_s)]
      end
    end

    def resolve(loader)
      @resolve_meta = {
        start_time: Process.clock_gettime(Process::CLOCK_MONOTONIC),
        current_loader: loader,
        perform_queue_sizes: loader.send(:queue).size
      }

      super
    end

    def around_promise_callbacks
      return super unless @resolve_meta

      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      TIMINGS[@resolve_meta[:current_loader].loader_key] ||= { times: [], perform_queue_sizes: [] }
      TIMINGS[@resolve_meta[:current_loader].loader_key][:times] << end_time - @resolve_meta[:start_time]
      TIMINGS[@resolve_meta[:current_loader].loader_key][:perform_queue_sizes] << @resolve_meta[:perform_queue_sizes]

      @resolve_meta = nil

      super
    end
  end
end
