# frozen_string_literal: true

require "test_helper"
require "test_schema"

class AnalyzerTest < ActiveSupport::TestCase
  REASONABLY_RECENT_UNIX_TIME = 1571337000 # aka 2019-10-17 in Unix time.
  SMALL_NONZERO_NUMBER = Float::EPSILON # aka 2.220446049250313e-16

  class SomeNumber
    include Comparable

    def initialize(at_least:)
      @at_least = at_least
    end

    def <=>(other)
      other >= @at_least ? 0 : nil
    end

    def to_s
      "SomeNumber: at least #{@at_least.to_s}"
    end
  end

  class SomeArgumentValue
    include Comparable

    def <=>(other)
      other.is_a?(GraphQL::Query::Arguments::ArgumentValue) ? 0 : nil
    end

    def to_s
      "SomeArgumentValue"
    end
  end

  class SimpleAnalyzer < GraphQLMetrics::Analyzer
    attr_reader :types_used, :context

    def initialize(query_or_multiplex)
      super

      @context = query_or_multiplex.context
      @context[:simple_extractor_results] = {}
    end

    def query_extracted(metrics)
      store_metrics(:queries, metrics)
    end

    def field_extracted(metrics)
      store_metrics(:fields, metrics)
    end

    def argument_extracted(metrics)
      store_metrics(:arguments, metrics)
    end

    private

    def store_metrics(context_key, metrics)
      context[:simple_extractor_results][context_key] ||= []
      context[:simple_extractor_results][context_key] << metrics
    end
  end

  class Schema < GraphQL::Schema
    query QueryRoot
    mutation MutationRoot

    use GraphQL::Batch
    use GraphQL::Execution::Interpreter
    use GraphQL::Analysis::AST

    instrument :query, GraphQLMetrics::Instrumentation
    query_analyzer SimpleAnalyzer
    tracer GraphQLMetrics::Tracer

    def self.parse_error(err, _context)
      return if err.is_a?(GraphQL::ParseError)
      raise err
    end
  end

  test 'extracts metrics from queries, as well as their fields and arguments' do
    query = GraphQL::Query.new(
      Schema,
      kitchen_sink_query_document,
      variables: { 'postId': '1', 'titleUpcase': true },
      operation_name: 'PostDetails',
    )
    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]

    actual_queries = results[:queries]
    actual_fields = results[:fields]
    actual_arguments = results[:arguments]

    expected_queries = [
      {
        :operation_type=>"query",
        :operation_name=>"PostDetails",
        :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
        :query_end_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
        :query_duration=>SomeNumber.new(at_least: 2),
        :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
      }
    ]

    assert_equal expected_queries, actual_queries

    # NOTE: Formatted with https://codebeautify.org/ruby-formatter-beautifier

    expected_fields = [{
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "id"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "title",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "title"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "ignoredAlias"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "deprecatedBody",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => true,
      :path => ["post", "deprecatedBody"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "id"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "body"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments", "id"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments", "body"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: 1)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }]
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "comments"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: 1)
      }]
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "otherComments", "id"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "otherComments", "body"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }, {
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "otherComments"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }]
    }, {
      :field_name => "post",
      :return_type_name => "Post",
      :parent_type_name => "QueryRoot",
      :deprecated => false,
      :path => ["post"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
      }],
      :lazy_resolver_timings => nil
    }]

    assert_equal(
      expected_fields,
      actual_fields,
      Diffy::Diff.new(JSON.pretty_generate(expected_fields), JSON.pretty_generate(actual_fields))
    )

    expected_arguments = [{
      :argument_name => "id",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "post",
      :parent_field_type_name => "QueryRoot",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "upcase",
      :argument_type_name => "Boolean",
      :default_used => false,
      :parent_field_name => "title",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "tags",
      :argument_type_name => "String",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => true,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Comment",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "tags",
      :argument_type_name => "String",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Comment",
      :value_is_null => true,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }]

    assert_equal(
      expected_arguments,
      actual_arguments,
      Diffy::Diff.new(JSON.pretty_generate(expected_arguments), JSON.pretty_generate(actual_arguments))
    )
  end

  test 'skips analysis, if the query is syntactically invalid' do
    query = GraphQL::Query.new(
      Schema,
      'HELLO',
    )

    analysis_results = GraphQL::Analysis::AST.analyze_query(query, [SimpleAnalyzer]).first
    assert_nil analysis_results
  end

  test 'skips analysis, if the query is semantically invalid' do
    query = GraphQL::Query.new(
      Schema,
      '{ foo { bar } }',
    )

    analysis_results = GraphQL::Analysis::AST.analyze_query(query, [SimpleAnalyzer]).first
    assert_nil analysis_results
  end

  test 'skips analysis, instrumentation and tracing if `skip_graphql_metrics_analysis` is set to true in the context' do
    query = GraphQL::Query.new(
      Schema,
      kitchen_sink_query_document,
      variables: { 'postId': '1', 'titleUpcase': true },
      operation_name: 'PostDetails',
      context: { skip_graphql_metrics_analysis: true }
    )
    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]

    assert_equal({}, results)
  end

  test 'extracts metrics manually via analyze call, with args supplied inline' do
    query = GraphQL::Query.new(
      Schema,
      mutation_document_inline_args,
      operation_name: 'PostCreate',
    )

    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]
    actual_arguments = results[:arguments]

    # NOTE: This test is passing simply to demonstrate the below `FIXME` argument value-related metrics.
    assert_equal(
      shared_expected_arguments_metrics,
      actual_arguments,
      Diffy::Diff.new(JSON.pretty_generate(shared_expected_arguments_metrics), JSON.pretty_generate(actual_arguments))
    )
  end

  test 'extracts metrics manually via analyze call with args supplied by variables' do
    query = GraphQL::Query.new(
      Schema,
      mutation_document,
      variables: {
        'postInput': {
          "title": "Hello",
          "body": "World!",
          "embeddedTags": [
            {
              "handle": "fun",
              "displayName": "Fun",
            },
          ],
        }
      },
      operation_name: 'PostCreate',
    )

    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]
    actual_arguments = results[:arguments]

    # NOTE: This test is failing to demonstrate the issue of input object fields not triggering the AST visitor's
    # on_enter/exit_argument hook.

    more_than_one_arg_extracted = actual_arguments.size > 1
    assert more_than_one_arg_extracted

    assert_equal(
      shared_expected_arguments_metrics,
      actual_arguments,
      Diffy::Diff.new(JSON.pretty_generate(shared_expected_arguments_metrics), JSON.pretty_generate(actual_arguments))
    )
  end

  # Note: the arguments metrics extracted should be the same, whether the query provided input object args inline or
  # via variables.
  def shared_expected_arguments_metrics
    [{
      :argument_name => "title",
      :argument_type_name => "String",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => "FIXME",
      :value => "FIXME",
      :default_used => "FIXME"
    }, {
      :argument_name => "body",
      :argument_type_name => "String",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => "FIXME",
      :value => "FIXME",
      :default_used => "FIXME"
    }, {
      :argument_name => "handle",
      :argument_type_name => "String",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => "FIXME",
      :value => "FIXME",
      :default_used => "FIXME"
    }, {
      :argument_name => "displayName",
      :argument_type_name => "String",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => "FIXME",
      :value => "FIXME",
      :default_used => "FIXME"
    }, {
      :argument_name => "embeddedTags",
      :argument_type_name => "TagInput",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => "FIXME",
      :value => "FIXME",
      :default_used => "FIXME"
    }, {
      :argument_name => "post",
      :argument_type_name => "PostInput",
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
      :default_used => false,
    }]
  end

  test 'extracts metrics from mutations' do
    query = GraphQL::Query.new(
      Schema,
      mutation_document,
      variables: {
        'postInput': {
          "title": "Hello",
          "body": "World!",
          "embeddedTags": [
            "handle": "fun",
            "displayName": "Fun",
          ],
        }
      },
      operation_name: 'PostCreate',
    )
    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]

    actual_queries = results[:queries]
    actual_fields = results[:fields]
    actual_arguments = results[:arguments]

    expected_queries = [
      {
        :operation_type=>"mutation",
        :operation_name=>"PostCreate",
        :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
        :query_end_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
        :query_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
      }
    ]
    assert_equal expected_queries, actual_queries

    # NOTE: Formatted with https://codebeautify.org/ruby-formatter-beautifier

    expected_fields = [{
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["postCreate", "post", "id"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "post",
      :return_type_name => "Post",
      :parent_type_name => "PostCreatePayload",
      :deprecated => false,
      :path => ["postCreate", "post"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
      }],
      :lazy_resolver_timings => nil
    }, {
      :field_name => "postCreate",
      :return_type_name => "PostCreatePayload",
      :parent_type_name => "MutationRoot",
      :deprecated => false,
      :path => ["postCreate"],
      :resolver_timings => [{
        :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
      }],
      :lazy_resolver_timings => nil
    }]

    assert_equal(
      expected_fields,
      actual_fields,
      Diffy::Diff.new(JSON.pretty_generate(expected_fields), JSON.pretty_generate(actual_fields))
    )

    expected_arguments = [{
      :argument_name => "post",
      :argument_type_name => "PostInput",
      :default_used => false,
      :parent_field_name => "postCreate",
      :parent_field_type_name => "MutationRoot",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }]

    assert_equal(
      expected_arguments,
      actual_arguments,
      Diffy::Diff.new(JSON.pretty_generate(expected_arguments), JSON.pretty_generate(actual_arguments))
    )
  end

  class Schema2 < GraphQL::Schema
    query QueryRoot
    mutation MutationRoot

    use GraphQL::Batch
    use GraphQL::Execution::Interpreter
    use GraphQL::Analysis::AST

    query_analyzer SimpleAnalyzer
  end

  test 'works as simple analyzer, gathering static metrics with no runtime data when the analyzer is not used as instrumentation and or a tracer' do
    query = GraphQL::Query.new(
      Schema2,
      kitchen_sink_query_document,
      variables: { 'postId': '1', 'titleUpcase': true },
      operation_name: 'PostDetails',
    )
    result = query.result.to_h

    refute result['errors'].present?
    assert result['data'].present?

    results = query.context[:simple_extractor_results]

    actual_queries = results[:queries]
    actual_fields = results[:fields]
    actual_arguments = results[:arguments]

    expected_queries = [
      {
        :operation_type=>"query",
        :operation_name=>"PostDetails",
      }
    ]

    assert_equal expected_queries, actual_queries

    expected_fields = [{
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "id"]
    }, {
      :field_name => "title",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "title"]
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "ignoredAlias"]
    }, {
      :field_name => "deprecatedBody",
      :return_type_name => "String",
      :parent_type_name => "Post",
      :deprecated => true,
      :path => ["post", "deprecatedBody"]
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "id"]
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "body"]
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments", "id"]
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments", "body"]
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "comments", "comments"]
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "comments"]
    }, {
      :field_name => "id",
      :return_type_name => "ID",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "otherComments", "id"]
    }, {
      :field_name => "body",
      :return_type_name => "String",
      :parent_type_name => "Comment",
      :deprecated => false,
      :path => ["post", "otherComments", "body"]
    }, {
      :field_name => "comments",
      :return_type_name => "Comment",
      :parent_type_name => "Post",
      :deprecated => false,
      :path => ["post", "otherComments"]
    }, {
      :field_name => "post",
      :return_type_name => "Post",
      :parent_type_name => "QueryRoot",
      :deprecated => false,
      :path => ["post"]
    }]

    assert_equal(
      expected_fields,
      actual_fields,
      Diffy::Diff.new(JSON.pretty_generate(expected_fields), JSON.pretty_generate(actual_fields))
    )

    expected_arguments = [{
      :argument_name => "id",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "post",
      :parent_field_type_name => "QueryRoot",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "upcase",
      :argument_type_name => "Boolean",
      :default_used => false,
      :parent_field_name => "title",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "tags",
      :argument_type_name => "String",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => true,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Comment",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "tags",
      :argument_type_name => "String",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Comment",
      :value_is_null => true,
      :value => SomeArgumentValue.new,
    }, {
      :argument_name => "ids",
      :argument_type_name => "ID",
      :default_used => false,
      :parent_field_name => "comments",
      :parent_field_type_name => "Post",
      :value_is_null => false,
      :value => SomeArgumentValue.new,
    }]

    assert_equal(
      expected_arguments,
      actual_arguments,
      Diffy::Diff.new(JSON.pretty_generate(expected_arguments), JSON.pretty_generate(actual_arguments))
    )
  end

  private

  def kitchen_sink_query_document
    <<~GRAPHQL
      query PostDetails($postId: ID!, $titleUpcase: Boolean = false, $commentsTags: [String!] = null) {
        post(id: $postId) {
          id
          title(upcase: $titleUpcase)

          ignoredAlias: body
          deprecatedBody

          comments(ids: [1, 2], tags: $commentsTags) { # 2 seconds recorded
            id
            body

            comments(ids: [5, 6], tags: $commentsTags) { # 2 seconds recorded
              id
              body
            }
          }

          otherComments: comments(ids: [3, 4]) { # ~0 seconds recorded, and that's correct because ids 3,4 are
            id                                   # loaded at the same time as 1,2 since they are the same field
            body                                 # invoked twice, whereas Comment.comments is a different field
          }                                      # than Post.comments
        }
      }

      query OperationNotSelected {
        post(id: "1") {
          id
        }
      }
    GRAPHQL
  end

  # TODO: Need nested inputs to test argument value extraction here, as well as in Shopify/shopify
  def mutation_document
    <<~GRAPHQL
      mutation PostCreate($postInput: PostInput!) {
        postCreate(post: $postInput) {
          post {
            id
          }
        }
      }

      query OperationNotSelected {
        post(id: "1") {
          id
        }
      }
    GRAPHQL
  end

  def mutation_document_inline_args
    inline_args = %{
      {
        title: "Hello",
        body: "World",
        embeddedTags: [
          {
            handle: "fun",
            displayName: "Fun",
          }
        ]
      }
    }

    <<~GRAPHQL
      mutation PostCreate {
        postCreate(post: #{inline_args}) {
          post {
            id
          }
        }
      }

      query OperationNotSelected {
        post(id: "1") {
          id
        }
      }
    GRAPHQL
  end
end
