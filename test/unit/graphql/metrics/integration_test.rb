# frozen_string_literal: true

require "test_helper"
require "test_schema"

module GraphQL
  module Metrics
    class IntegrationTest < ActiveSupport::TestCase
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

      class SimpleAnalyzer < GraphQL::Metrics::Analyzer
        ANALYZER_NAMESPACE = :simple_analyzer_namespace

        attr_reader :types_used, :context

        def initialize(query_or_multiplex)
          super

          @context = query_or_multiplex.context.namespace(ANALYZER_NAMESPACE)
          @context[:simple_extractor_results] = {
            queries: [],
            fields: [],
            arguments: [],
            deprecated_enum_values: [],
          }
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

        def enum_value_extracted(metrics)
          store_metrics(:deprecated_enum_values, metrics)
        end

        private

        def store_metrics(context_key, metrics)
          context[:simple_extractor_results][context_key] << metrics
        end
      end

      class SchemaWithFullMetrics < GraphQL::Schema
        query QueryRoot
        mutation MutationRoot

        use GraphQL::Batch
        use GraphQL::Execution::Interpreter
        use GraphQL::Analysis::AST

        instrument :query, GraphQL::Metrics::Instrumentation.new
        query_analyzer SimpleAnalyzer
        tracer GraphQL::Metrics::Tracer.new

        def self.parse_error(err, _context)
          return if err.is_a?(GraphQL::ParseError)
          raise err
        end
      end

      test 'extracts metrics from queries, as well as their fields, arguments and any deprecated enum values used' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]
        actual_deprecated_enum_values = results[:deprecated_enum_values]

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, actual_queries)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, actual_fields)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, actual_arguments)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_deprecated_enum_values, actual_deprecated_enum_values)
      end

      focus
      test 'extracts metrics in all of the same ways, when a multiplex is executed' do
        queries = [
          {
            query: 'query OtherQuery { post(id: "42") { id title } }',
            operation_name: 'OtherQuery',
          },
          {
            query: kitchen_sink_query_document,
            variables: { 'postId': '1', 'titleUpcase': true },
            operation_name: 'PostDetails',
          },
        ]

        multiplex_results = SchemaWithFullMetrics.multiplex(queries)

        metrics_results = multiplex_results.map do |multiplex_result|
          metrics_result = multiplex_result
            .query
            .context
            .namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

          {
            queries: metrics_result[:queries],
            fields: metrics_result[:fields],
            arguments: metrics_result[:arguments],
          }
        end

        other_query_metrics = metrics_results[0]
        kitchen_sink_query_metrics = metrics_results[1]

        expected_other_query_queries = [{
          :operation_type => "query",
          :operation_name => "OtherQuery",
          :query_start_time => SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
          :query_duration => SomeNumber.new(at_least: 2),
          :parsing_start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :parsing_duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :validation_start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :validation_duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
        }]

        expected_other_query_fields = [{
          :field_name => "id",
          :return_type_name => "ID",
          :parent_type_name => "Post",
          :deprecated => false,
          :path => ["post", "id"],
          :resolver_timings => [{
            :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          }],
          :lazy_resolver_timings => [],
        }, {
          :field_name => "title",
          :return_type_name => "String",
          :parent_type_name => "Post",
          :deprecated => false,
          :path => ["post", "title"],
          :resolver_timings => [{
            :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          }],
          :lazy_resolver_timings => [],
        }, {
          :field_name => "post",
          :return_type_name => "Post",
          :parent_type_name => "QueryRoot",
          :deprecated => false,
          :path => ["post"],
          :resolver_timings => [{
            :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          }],
          :lazy_resolver_timings => [],
        }]

        expected_other_query_arguments = [{
          :argument_name => "id",
          :argument_type_name => "ID",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        },
        {
          :argument_name => "subject",
          :argument_type_name => "PostSubject",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }]

        assert_equal_with_diff_on_failure(expected_other_query_queries, other_query_metrics[:queries])
        assert_equal_with_diff_on_failure(expected_other_query_fields, other_query_metrics[:fields])
        assert_equal_with_diff_on_failure(expected_other_query_arguments, other_query_metrics[:arguments])

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, kitchen_sink_query_metrics[:queries])
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, kitchen_sink_query_metrics[:fields])
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, kitchen_sink_query_metrics[:arguments])
      end

      test 'skips logging for fields and arguments if `skip_field_and_argument_metrics: true` in context' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: {
            GraphQL::Metrics::SKIP_FIELD_AND_ARGUMENT_METRICS => true,
          }
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, actual_queries)
        assert_equal [], actual_fields
        assert_equal [], actual_arguments
      end

      test 'skips analysis, if the query is syntactically invalid' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          'HELLO',
        )

        analysis_results = GraphQL::Analysis::AST.analyze_query(query, [SimpleAnalyzer]).first
        assert_nil analysis_results
      end

      test 'skips analysis, if the query is semantically invalid' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          '{ foo { bar } }',
        )

        analysis_results = GraphQL::Analysis::AST.analyze_query(query, [SimpleAnalyzer]).first
        assert_nil analysis_results
      end

      test 'skips analysis, if the query is valid but blank' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          '# Welcome to GraphiQL !',
        )

        analysis_results = GraphQL::Analysis::AST.analyze_query(query, [SimpleAnalyzer]).first
        assert_nil analysis_results
      end

      test 'skips analysis, instrumentation and tracing if `skip_graphql_metrics_analysis` is set to true in the context' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: { skip_graphql_metrics_analysis: true }
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        expected = {:queries=>[], :fields=>[], :arguments=>[], :deprecated_enum_values=>[]}
        assert_equal(expected, results)
      end

      test 'extracts metrics manually via analyze call, with args supplied inline' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          mutation_document_inline_args,
          operation_name: 'PostCreate',
        )

        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(shared_expected_arguments_metrics, actual_arguments)
      end

      test 'extracts metrics manually via analyze call with args supplied by variables' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
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

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(shared_expected_arguments_metrics, actual_arguments)
      end

      test 'fields requested that are not resolved (e.g. id for a post that itself was never resolved) produce no inline field timings' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          '{ post(id: "missing_post") { id } }',
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        actual_fields = results[:fields]
        id_field_metric = actual_fields.find { |f| f[:path] == %w(post id) }

        assert_equal [], id_field_metric[:resolver_timings]
      end

      # Note: Arguments metrics extracted should be the same, whether the query provided input object args inline or
      # via variables.
      def shared_expected_arguments_metrics
        [{
          :argument_name => "post",
          :argument_type_name => "PostInput",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "title",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "body",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "embeddedTags",
          :argument_type_name => "TagInput",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "handle",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "displayName",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]
      end

      test 'extracts metrics from mutations, input objects' do
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
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

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        expected_queries = [
          {
            :operation_type=>"mutation",
            :operation_name=>"PostCreate",
            :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
            :query_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          }
        ]

        assert_equal_with_diff_on_failure(expected_queries, actual_queries)

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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
        }]

        assert_equal_with_diff_on_failure(expected_fields, actual_fields)

        expected_arguments = [{
          :argument_name => "post",
          :argument_type_name => "PostInput",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "title",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "body",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "embeddedTags",
          :argument_type_name => "TagInput",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "handle",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "displayName",
          :argument_type_name => "String",
          :parent_field_name => "postCreate",
          :parent_field_type_name => "MutationRoot",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]

        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments)
      end

      class SchemaWithoutTimingMetrics < GraphQL::Schema
        query QueryRoot
        mutation MutationRoot

        use GraphQL::Batch
        use GraphQL::Execution::Interpreter
        use GraphQL::Analysis::AST

        query_analyzer SimpleAnalyzer
      end

      test 'works as simple analyzer, gathering static metrics with no runtime data when the analyzer is not used as instrumentation and or a tracer' do
        query = GraphQL::Query.new(
          SchemaWithoutTimingMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        expected_queries = [
          {
            :operation_type=>"query",
            :operation_name=>"PostDetails",
          }
        ]

        assert_equal_with_diff_on_failure(expected_queries, actual_queries)

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

        assert_equal_with_diff_on_failure(expected_fields, actual_fields)

        expected_arguments = [{
          :argument_name => "upcase",
          :argument_type_name => "Boolean",
          :parent_field_name => "title",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "truncate",
          :argument_type_name => "Boolean",
          :parent_field_name => "body",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Comment",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_field_name => "comments",
          :parent_field_type_name => "Comment",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "id",
          :argument_type_name => "ID",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        },
        {
          :argument_name => "subject",
          :argument_type_name => "PostSubject",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]

        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments)
      end

      test 'handles input objects with no required fields (ONE of which has a default) are passed in as `{}`' do
        query_document = <<~GRAPHQL
          mutation PostUpdate {
            postUpdate(post: {}) {
              success
            }
          }
        GRAPHQL

        query = GraphQL::Query.new(SchemaWithFullMetrics, query_document)
        result = query.result.to_h
        refute result['errors'].present?
        assert result['data'].present?

        metrics_results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]
        actual_arguments = metrics_results[:arguments]

        expected_arguments = [
          {
            :argument_name=>"post",
            :argument_type_name=>"PostUpdateInput",
            :parent_field_name=>"postUpdate",
            :parent_field_type_name=>"MutationRoot",
            :parent_input_object_type=>nil,
            :default_used=>false,
            :value_is_null=>false,
            :value => SomeArgumentValue.new,
          },
          {
            :argument_name=> "title",
            :argument_type_name=> "String",
            :parent_field_name=> "postUpdate",
            :parent_field_type_name=> "MutationRoot",
            :parent_input_object_type=> "PostUpdateInput",
            :default_used=> true,
            :value_is_null=> false,
            :value => SomeArgumentValue.new,
          }
        ]

        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments)
      end

      test 'handles input objects with no required fields (NONE of which have a default) are passed in as `{}`' do
        query_document = <<~GRAPHQL
          mutation PostUpvote {
            postUpvote(upvote: {}) {
              success
            }
          }
        GRAPHQL

        query = GraphQL::Query.new(SchemaWithFullMetrics, query_document)
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        metrics_results = query.context.namespace(SimpleAnalyzer::ANALYZER_NAMESPACE)[:simple_extractor_results]
        actual_arguments = metrics_results[:arguments]

        expected_arguments = [
          {
            :argument_name=>"upvote",
            :argument_type_name=>"PostUpvoteInput",
            :parent_field_name=>"postUpvote",
            :parent_field_type_name=>"MutationRoot",
            :parent_input_object_type=>nil,
            :default_used=>false,
            :value_is_null=>false,
            :value => SomeArgumentValue.new,
          }
        ]

        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments)
      end

      private

      def assert_equal_with_diff_on_failure(expected, actual)
        assert_equal(
          expected,
          actual,
          Diffy::Diff.new(JSON.pretty_generate(expected), JSON.pretty_generate(actual))
        )
      end

      def kitchen_sink_expected_queries
        # NOTE: Formatted with https://codebeautify.org/ruby-formatter-beautifier
        [
          {
            :operation_type=>"query",
            :operation_name=>"PostDetails",
            :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
            :query_duration=>SomeNumber.new(at_least: 2),
            :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          }
        ]
      end

      def kitchen_sink_expected_fields
        [{
          :field_name => "id",
          :return_type_name => "ID",
          :parent_type_name => "Post",
          :deprecated => false,
          :path => ["post", "id"],
          :resolver_timings => [{
            :start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER)
          }],
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
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
          :lazy_resolver_timings => [],
        }]
      end

      def kitchen_sink_expected_arguments
        [{
          :argument_name => "upcase",
          :argument_type_name => "Boolean",
          :parent_field_name => "title",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "truncate",
          :argument_type_name => "Boolean",
          :parent_field_name => "body",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Comment",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_field_name => "comments",
          :parent_field_type_name => "Comment",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_field_name => "comments",
          :parent_field_type_name => "Post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "id",
          :argument_type_name => "ID",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        },
        {
          :argument_name => "subject",
          :argument_type_name => "PostSubject",
          :parent_field_name => "post",
          :parent_field_type_name => "QueryRoot",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]
      end

      def kitchen_sink_expected_deprecated_enum_values
        [{
          :argument_name=>"subject",
          :argument_type_name=>"PostSubject",
          :default_used=>false,
          :deprecated=>true,
          :value=>"RANDOM"
        }]
      end

      def kitchen_sink_query_document
        <<~GRAPHQL
          query PostDetails($postId: ID!, $titleUpcase: Boolean = false, $commentsTags: [String!] = null) {
            post(id: $postId, subject: RANDOM) {
              __typename # Ignored
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
  end
end
