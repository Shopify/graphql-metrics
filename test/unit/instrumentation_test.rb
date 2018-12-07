# frozen_string_literal: true

require "test_helper"
require "test_schema"
require "redis_instrumentation"

class InstrumentationTest < ActiveSupport::TestCase
  class Schema < GraphQL::Schema
    query QueryRoot
    mutation MutationRoot

    use GraphQLMetrics::RedisInstrumentation
    use GraphQL::Batch, executor_class: GraphQLMetrics::TimedBatchExecutor

    def self.object_from_id(id, _query_ctx)
      class_name, item_id = id.split('-')

      case class_name
      when 'Post'
        OpenStruct.new(id: item_id, title: 'Foo', body: "Bar", comments: [])
      when 'Comment'
        OpenStruct.new(id: item_id, body: "Baz")
      end
    end

    def self.resolve_type(_type, obj, _ctx)
      if obj.respond_to?(:title)
        Post
      else
        Comment
      end
    end
  end

  setup do
    Process.stubs(clock_gettime: 0)

    @redis = Redis.new
    @redis.flushall
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

      query OtherQuery($unusedPostId: ID!) {
        post(id: $unusedPostId) {
          id
        }
      }
    QUERY

    result_hash = Schema.execute(
      query_string,
      variables: {
        'postId': '1',
        'titleUpcase': true,
        'unusedPostId': '1'
      },
      operation_name: 'MyQuery'
    )

    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      queries: extract_from_redis('query_extracted'),
      fields: extract_from_redis('field_extracted'),
      arguments: extract_from_redis('argument_extracted'),
      variables: extract_from_redis('variable_extracted'),
      batch_loaded_fields: extract_from_redis('batch_loaded_field_extracted'),
    }

    expected = {
      queries: [
        {
          operation_type: "query",
          operation_name: "MyQuery",
          duration: 0
        }
      ],
      fields: [
        { type_name: "QueryRoot", field_name: "post", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "id", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "title", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "body", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "deprecatedBody", deprecated: true, resolver_times: [0] },
        { type_name: "Post", field_name: "comments", deprecated: false, resolver_times: [0] },
        { type_name: "Comment", field_name: "id", deprecated: false, resolver_times: [0, 0] },
        { type_name: "Comment", field_name: "body", deprecated: false, resolver_times: [0, 0] },
        { type_name: "Post", field_name: "comments", deprecated: false, resolver_times: [0] },
        { type_name: "Comment", field_name: "id", deprecated: false, resolver_times: [0, 0] },
        { type_name: "Comment", field_name: "body", deprecated: false, resolver_times: [0, 0] }
      ],
      arguments: [
        { name: "id", type: "ID", value_is_null: false, default_used: false, parent_input_type: nil,
          field_name: "post", field_base_type: "QueryRoot" },
        { name: "locale", type: "String", value_is_null: false, default_used: true, parent_input_type: nil,
          field_name: "post", field_base_type: "QueryRoot" },
        { name: "upcase", type: "Boolean", value_is_null: false, default_used: false, parent_input_type: nil,
          field_name: "title", field_base_type: "Post" },
        { name: "truncate", type: "Boolean", value_is_null: false, default_used: true, parent_input_type: nil,
          field_name: "body", field_base_type: "Post" },
        { name: "ids", type: "ID", value_is_null: false, default_used: false, parent_input_type: nil,
          field_name: "comments", field_base_type: "Post" },
        { name: "tags", type: "String", value_is_null: true, default_used: false, parent_input_type: nil,
          field_name: "comments", field_base_type: "Post" },
        { name: "ids", type: "ID", value_is_null: false, default_used: false, parent_input_type: nil,
          field_name: "comments", field_base_type: "Post" }
      ],
      variables: [
        {
          operation_name: "MyQuery",
          unwrapped_type_name: "ID",
          type: "ID!",
          default_value_type: "IMPLICIT_NULL",
          provided_value: false,
          default_used: false,
          used_in_operation: true
        },
        {
          operation_name: "MyQuery",
          unwrapped_type_name: "Boolean",
          type: "Boolean",
          default_value_type: "NON_NULL",
          provided_value: false,
          default_used: true,
          used_in_operation: true
        },
        {
          operation_name: "MyQuery",
          unwrapped_type_name: "String",
          type: "[String!]",
          default_value_type: "EXPLICIT_NULL",
          provided_value: false,
          default_used: true,
          used_in_operation: true
        },
        {
          operation_name: "OtherQuery",
          unwrapped_type_name: "ID",
          type: "ID!",
          default_value_type: "IMPLICIT_NULL",
          provided_value: false,
          default_used: false,
          used_in_operation: false
        }
      ],
      batch_loaded_fields: [
        {
          key: "CommentLoader/Comment",
          identifiers: [],
          times: [0],
          perform_queue_sizes: [4]
        }
      ]
    }

    assert_equal expected, actual, Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
  end

  test 'extracts metrics mutations' do
    query_string = <<~QUERY
      mutation MyMutation($post: PostInput!) {
        postCreate(post: $post) {
          post {
            id
            title
            body
          }
        }
      }
    QUERY

    result_hash = Schema.execute(query_string, variables: { post: { title: 'Hi', body: 'Hello' } })
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      queries: extract_from_redis('query_extracted'),
      fields: extract_from_redis('field_extracted'),
      arguments: extract_from_redis('argument_extracted'),
      variables: extract_from_redis('variable_extracted'),
      batch_loaded_fields: extract_from_redis('batch_loaded_field_extracted'),
    }

    expected = {
      queries: [
        {
          operation_type: "mutation",
          operation_name: "MyMutation",
          duration: 0
        }
      ],
      fields: [
        { type_name: "MutationRoot", field_name: "postCreate", deprecated: false, resolver_times: [0] },
        { type_name: "PostCreatePayload", field_name: "post", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "id", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "title", deprecated: false, resolver_times: [0] },
        { type_name: "Post", field_name: "body", deprecated: false, resolver_times: [0] }
      ],
      arguments: [
        {
          name: "post",
          type: "PostInput",
          value_is_null: false,
          default_used: false,
          parent_input_type: nil,
          field_name: "postCreate",
          field_base_type: "MutationRoot"
        },
        {
          name: "title",
          type: "String",
          value_is_null: false,
          default_used: false,
          parent_input_type: "PostInput",
          field_name: "postCreate",
          field_base_type: "MutationRoot"
        },
        {
          name: "body",
          type: "String",
          value_is_null: false,
          default_used: false,
          parent_input_type: "PostInput",
          field_name: "postCreate",
          field_base_type: "MutationRoot"
        },
        {
          name: "truncate",
          type: "Boolean",
          value_is_null: false,
          default_used: true,
          parent_input_type: nil,
          field_name: "body",
          field_base_type: "Post"
        }
      ],
      variables: [
        {
          operation_name: "MyMutation",
          unwrapped_type_name: "PostInput",
          type: "PostInput!",
          default_value_type: "IMPLICIT_NULL",
          provided_value: false,
          default_used: false,
          used_in_operation: true
        }
      ],
      batch_loaded_fields: []
    }

    assert_equal expected, actual, Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
  end

  test 'extractor with `before_query_extracted` callback' do
    class ExtractorWithCallbacks < GraphQLMetrics::Instrumentation
      attr_reader :from_context

      def before_query_extracted(_query, query_context)
        Redis.new.set('something_from_context', query_context[:foo])
      end
    end

    class Schema2 < GraphQL::Schema
      query QueryRoot
      mutation MutationRoot

      use ExtractorWithCallbacks
    end

    result_hash = Schema2.execute(minimal_query, context: { foo: 'bar' })
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    assert_equal 'bar', Redis.new.get('something_from_context')
  end

  test "extractor with `skip_field_resolution_timing?` callback doesn't log field resolver times" do
    class ExtractorSkipsFieldResolutionTiming < GraphQLMetrics::RedisInstrumentation
      def skip_field_resolution_timing?(_query, _ctx)
        true
      end
    end

    class Schema3 < GraphQL::Schema
      query QueryRoot
      mutation MutationRoot

      use ExtractorSkipsFieldResolutionTiming
    end

    result_hash = Schema3.execute(minimal_query)
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual_fields = extract_from_redis('field_extracted')
    actual_resolver_times = actual_fields.map {|f| f[:resolver_times]}
    assert actual_resolver_times.all? { |rt| rt.empty? }, actual_resolver_times
  end

  test "extractor with `skip_extraction?` callback doesn't log anything" do
    class ExtractorSkipsAllLogging < GraphQLMetrics::RedisInstrumentation
      def skip_extraction?(_query)
        true
      end
    end

    class Schema4 < GraphQL::Schema
      query QueryRoot
      mutation MutationRoot

      use ExtractorSkipsAllLogging
    end

    result_hash = Schema4.execute(minimal_query)
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      queries: extract_from_redis('query_extracted'),
      fields: extract_from_redis('field_extracted'),
      arguments: extract_from_redis('argument_extracted'),
      variables: extract_from_redis('variable_extracted'),
      batch_loaded_fields: extract_from_redis('batch_loaded_field_extracted'),
    }

    assert actual.values.all? { |v| v.empty? }
  end

  test 'references to QueryRoot.node#id do not emit n field usage events for all types that implement Node' do
    query_string = <<~QUERY
      query MyQuery {
        node(id: "Comment-1") {
          id
        }
      }
    QUERY

    result_hash = Schema.execute(query_string)
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      fields: extract_from_redis('field_extracted'),
    }

    expected = {
      fields: [
        { type_name: "QueryRoot", field_name: "node", deprecated: false, resolver_times: [0] },
        { type_name: "Node", field_name: "id", deprecated: false, resolver_times: [0] },
      ],
    }

    assert_equal expected, actual, Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
  end

  test 'references to QueryRoot.node#id do not emit n field usage events for all types that implement Node when pattern matching' do
    query_string = <<~QUERY
      query MyQuery {
        node(id: "Comment-1") {
          ... on Comment {
            id
          }
        }
      }
    QUERY

    result_hash = Schema.execute(query_string)
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      fields: extract_from_redis('field_extracted'),
    }

    expected = {
      fields: [
        { type_name: "QueryRoot", field_name: "node", deprecated: false, resolver_times: [0] },
        { type_name: "Comment", field_name: "id", deprecated: false, resolver_times: [0] },
      ],
    }

    assert_equal expected, actual, Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
  end

  test 'references to QueryRoot.nodes#id do not emit n field usage events for all types that implement Node' do
    query_string = <<~QUERY
      query MyQuery {
        nodes(ids: ["Comment-1"]) {
          id
        }
      }
    QUERY

    result_hash = Schema.execute(query_string)
    assert_nil result_hash['errors']
    refute_nil result_hash['data']

    actual = {
      fields: extract_from_redis('field_extracted'),
    }

    expected = {
      fields: [
        { type_name: "QueryRoot", field_name: "nodes", deprecated: false, resolver_times: [0] },
        { type_name: "Node", field_name: "id", deprecated: false, resolver_times: [0] },
      ],
    }

    assert_equal expected, actual, Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
  end

  test 'can be passed as an instance, to an instance of a schema, with Schema#use' do
    instumentation_instance = GraphQLMetrics::RedisInstrumentation.new
    schema_instance = Schema.new

    assert_nothing_raised do
      schema_instance.redefine do |schema|
        use(instumentation_instance)
      end
    end
  end

  private

  def minimal_query
    <<~QUERY
      query MyMinimalQuery {
        post(id: 1) {
          id
        }
      }
    QUERY
  end

  def extract_from_redis(key)
    @redis.lrange(key, 0, -1).map { |v| eval v }.reverse
  end
end
