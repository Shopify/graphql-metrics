# frozen_string_literal: true

require "test_helper"
require "test_schema"

class NonInstrumentationExtractorTest < ActiveSupport::TestCase
  class TypeUsageExtractor < GraphQLMetrics::Extractor
    attr_reader :types_used

    def initialize
      @types_used = Set.new
    end

    def field_extracted(metrics, _metadata)
      @types_used << metrics[:type_name]
    end

    # Note: The below methods are implemented simply for test coverage (extractor code paths will be run, but their
    # data won't be used.)

    def query_extracted(_metrics, _metadata)
      # No op
    end

    def batch_loaded_field_extracted(_metrics, _metadata)
      # No op
    end

    def argument_extracted(_metrics, _metadata)
      # No op
    end

    def variable_extracted(_metrics, _metadata)
      # No op
    end

    def before_query_extracted(_query, query_context)
      # No op
    end

    def skip_extraction?(_query)
      # No op
    end

    def skip_field_resolution_timing?(_query, _metadata)
      # No op
    end

    def after_query_teardown(_query)
      # No op
    end
  end

  class Schema < GraphQL::Schema
    query QueryRoot
    mutation MutationRoot

    use GraphQL::Batch
  end

  test 'extracts metrics queries' do
    query_string = <<~QUERY
      query MyQuery($postId: ID!, $titleUpcase: Boolean = false, $commentsTags: [String!] = null) {
        post(id: $postId) {
          id
          title(upcase: $titleUpcase)

          ignoredAlias: body
          deprecatedBody

          comments(ids: [1, 2], tags: $commentsTags) {
            id
            body
          }

          otherComments: comments(ids: [3, 4]) {
            id
            body
          }
        }
      }
    QUERY

    query = GraphQL::Query.new(
      Schema,
      query_string,
      variables: { 'postId': '1', 'titleUpcase': true },
    )

    extractor = TypeUsageExtractor.new
    extractor.extract!(query)

    assert_equal %w(Comment Post QueryRoot), extractor.types_used.sort
  end
end
