# frozen_string_literal: true

module GraphQLMetrics
  class RedisExtractor < GraphQLMetrics::Extractor
    def initialize
      @redis = Redis.new
    end

    def query_extracted(metrics, _metadata)
      @redis.lpush(
        'query_extracted',
        {
          query_string: metrics[:query_string],
          operation_type: metrics[:operation_type],
          operation_name: metrics[:operation_name],
          duration: metrics[:duration],
        }
      )
    end

    def field_extracted(metrics, _metadata)
      @redis.lpush(
        'field_extracted',
        {
          type_name: metrics[:type_name],
          field_name: metrics[:field_name],
          deprecated: metrics[:deprecated],
          resolver_times: metrics[:resolver_times],
        }
      )
    end

    def batch_loaded_field_extracted(metrics, _metadata)
      @redis.lpush(
        'batch_loaded_field_extracted',
        {
          key: metrics[:key],
          identifiers: metrics[:identifiers],
          times: metrics[:times],
          perform_queue_sizes: metrics[:perform_queue_sizes],
        }
      )
    end

    def argument_extracted(metrics, _metadata)
      @redis.lpush(
        'argument_extracted',
        {
          name: metrics[:name],
          type: metrics[:type],
          value_is_null: metrics[:value_is_null],
          default_used: metrics[:default_used],
          parent_input_type: metrics[:parent_input_type],
          field_name: metrics[:field_name],
          field_base_type: metrics[:field_base_type],
        }
      )
    end

    def variable_extracted(metrics, _metadata)
      @redis.lpush(
        'variable_extracted',
        {
          operation_name: metrics[:operation_name],
          unwrapped_type_name: metrics[:unwrapped_type_name],
          type: metrics[:type],
          default_value_type: metrics[:default_value_type],
          provided_value: metrics[:provided_value],
          default_used: metrics[:default_used],
          used_in_query: metrics[:used_in_query],
        }
      )
    end
  end
end
