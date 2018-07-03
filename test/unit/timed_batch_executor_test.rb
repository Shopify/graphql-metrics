# frozen_string_literal: true

require 'test_helper'

class TimedBatchExecutorTest < ActiveSupport::TestCase
  class Post
    def id
      42
    end
  end

  test ".serialize_loader_key logs GraphQL batch resolution details to Kafka, serializing elements of the batch loader key for human readability, substituting '?' when an element is not handled" do
    post = Post.new

    raw_key = [post, 'string', 42, :symbol, Class, { foo: :bar }]
    expected_key = "TimedBatchExecutorTest::Post/_/string/_/symbol/Class/?"
    expected_identifiers = [post.id, 42].map(&:to_s)

    key, identifiers = GraphQLMetrics::TimedBatchExecutor.serialize_loader_key(raw_key)

    assert_equal expected_key, key
    assert_equal expected_identifiers, identifiers
  end
end
