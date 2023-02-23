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
          other.is_a?(GraphQL::Execution::Interpreter::ArgumentValue) ? 0 : nil
        end

        def to_s
          "SomeArgumentValue"
        end
      end

      class SimpleAnalyzer < GraphQL::Metrics::Analyzer
        attr_reader :types_used, :context

        def initialize(query_or_multiplex)
          super

          @context = query_or_multiplex.context
          @context[:simple_extractor_results] = {
            queries: [],
            fields: [],
            arguments: [],
            directives: [],
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

        def directive_extracted(metrics)
          store_metrics(:directives, metrics)
        end

        private

        def store_metrics(context_key, metrics)
          @context[:simple_extractor_results][context_key] << metrics
        end
      end

      class SchemaWithFullMetrics < GraphQL::Schema
        query QueryRoot
        mutation MutationRoot
        directive CustomDirective

        use GraphQL::Batch

        instrument :query, GraphQL::Metrics::Instrumentation.new
        query_analyzer SimpleAnalyzer
        tracer GraphQL::Metrics::Tracer.new

        def self.parse_error(err, _context)
          return if err.is_a?(GraphQL::ParseError)
          raise err
        end
      end

      test 'extracts metrics from queries, as well as their fields and arguments (when using Query#result)' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, actual_queries)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, actual_fields)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, actual_arguments)
      end

      test 'metrics for directives are empty if no directives are found' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1' },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_directives = results[:directives]

        assert_equal_with_diff_on_failure([], actual_directives)
      end

      test 'extracts metrics from directives on QUERY and FIELD location' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          query_document_with_directive,
          variables: { 'postId': '1', 'titleUpcase': true, 'val': 10 },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_directives = results[:directives]
        actual_arguments = results[:arguments]

        expected_arguments = [
          {
            argument_name: "if",
            argument_type_name: "Boolean",
            parent_name: "skip",
            grandparent_type_name: "__Directive",
            grandparent_node_name: "title",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "id",
            argument_type_name: "ID",
            parent_name: "post",
            grandparent_type_name: "QueryRoot",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "locale",
            argument_type_name: "String",
            parent_name: "post",
            grandparent_type_name: "QueryRoot",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: true,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "val",
            argument_type_name: "Int",
            parent_name: "customDirective",
            grandparent_type_name: "__Directive",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new
          }
        ]

        assert_equal_with_diff_on_failure(
          [{ directive_name: 'skip' }, { directive_name: 'customDirective' }],
          actual_directives,
          sort_by: ->(x) { x[:directive_name] }
        )

        assert_equal_with_diff_on_failure(
          expected_arguments,
          actual_arguments,
          sort_by: ->(x) { x[:argument_name] }
        )
      end

      test 'extracts metrics from directives on MUTATION location' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          mutation_document_with_directive,
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
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_directives = results[:directives]
        actual_arguments = results[:arguments]

        expected_arguments = [
          {
              argument_name: "post",
              argument_type_name: "PostInput",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: nil,
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "title",
              argument_type_name: "String",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: "PostInput",
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "body",
              argument_type_name: "String",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: "PostInput",
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "embeddedTags",
              argument_type_name: "TagInput",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: "PostInput",
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "handle",
              argument_type_name: "String",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: "TagInput",
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "displayName",
              argument_type_name: "String",
              parent_name: "postCreate",
              grandparent_type_name: "MutationRoot",
              grandparent_node_name: "mutation",
              parent_input_object_type: "TagInput",
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }, {
              argument_name: "val",
              argument_type_name: "Int",
              parent_name: "customDirective",
              grandparent_type_name: "__Directive",
              grandparent_node_name: "mutation",
              parent_input_object_type: nil,
              default_used: false,
              value_is_null: false,
              value: SomeArgumentValue.new,
            }
          ]
        assert_equal_with_diff_on_failure([{ directive_name: 'customDirective' }], actual_directives)
        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments, sort_by: ->(x) { x[:argument_name] })
      end

      test 'extracts metrics from directives on QUERY and FIELD location for document with fragment' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          query_document_with_fragment,
          variables: { 'postId': 1, 'titleUpcase': true, 'val': 10 },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_directives = results[:directives]
        actual_arguments = results[:arguments]

        expected_arguments = [
          {
            argument_name: "if",
            argument_type_name: "Boolean",
            parent_name: "skip",
            grandparent_type_name: "__Directive",
            grandparent_node_name: "id",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "upcase",
            argument_type_name: "Boolean",
            parent_name: "title",
            grandparent_type_name: "Post",
            grandparent_node_name: "Post",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "id",
            argument_type_name: "ID",
            parent_name: "post",
            grandparent_type_name: "QueryRoot",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "locale",
            argument_type_name: "String",
            parent_name: "post",
            grandparent_type_name: "QueryRoot",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: true,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }, {
            argument_name: "val",
            argument_type_name: "Int",
            parent_name: "customDirective",
            grandparent_type_name: "__Directive",
            grandparent_node_name: "query",
            parent_input_object_type: nil,
            default_used: false,
            value_is_null: false,
            value: SomeArgumentValue.new,
          }
        ]

        assert_equal_with_diff_on_failure(
          [{ directive_name: 'skip' }, { directive_name: 'customDirective' }],
          actual_directives,
          sort_by: -> (x) { x[:directive_name] }
        )
        assert_equal_with_diff_on_failure(
          expected_arguments,
          actual_arguments,
          sort_by: -> (x) { x[:argument_name] }
        )
      end

      test 'extracts metrics from queries, as well as their fields and arguments (when using Schema.execute)' do
        context = {}
        result = SchemaWithFullMetrics.execute(
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, actual_queries)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, actual_fields)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, actual_arguments)
      end

      test 'extracts metrics from queries, as well as their fields and arguments (when using Schema.execute), even with validation skipped' do
        context = {}
        result = SchemaWithFullMetrics.execute(
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context,
          validate: false
        )

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, actual_queries)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, actual_fields)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, actual_arguments)
      end

      test 'extracts metrics from queries that have already been parsed, omitting parsing timings' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          document: GraphQL.parse(kitchen_sink_query_document),
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        expected_queries = [
          {
            :operation_type=>"query",
            :operation_name=>"PostDetails",
            :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
            :query_duration=>SomeNumber.new(at_least: 2),
            :lexing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :lexing_duration=>SomeNumber.new(at_least: 0),
            :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_duration=>SomeNumber.new(at_least: 0),
            :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :multiplex_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
          }
        ]
        assert_equal_with_diff_on_failure(expected_queries, actual_queries)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, actual_fields)
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, actual_arguments)
      end

      test 'parsing metrics are properly reset when a second query is initialized with a document' do
        first_query_context = {}

        GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: first_query_context,
        ).result

        first_query_result = first_query_context[:simple_extractor_results][:queries][0]

        second_query_context = {}

        GraphQL::Query.new(
          SchemaWithFullMetrics,
          nil,
          document: GraphQL.parse(kitchen_sink_query_document),
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: second_query_context,
        ).result

        second_query_result = second_query_context[:simple_extractor_results][:queries][0]

        assert(first_query_result[:lexing_start_time_offset] < second_query_result[:lexing_start_time_offset])
        assert(first_query_result[:parsing_start_time_offset] < second_query_result[:parsing_start_time_offset])
        assert_equal(0.0, second_query_result[:lexing_duration])
        assert_equal(0.0, second_query_result[:parsing_duration])
      end

      test 'GraphQL::Querys executed in the same thread have increasing `multiplex_start_time`s (regression test; see below)' do
        multiplex_start_times = 2.times.map do
          context = {}
          query = GraphQL::Query.new(
            SchemaWithFullMetrics,
            kitchen_sink_query_document,
            variables: { 'postId': '1', 'titleUpcase': true },
            operation_name: 'PostDetails',
            context: context
          )
          result = query.result.to_h

          results = context[:simple_extractor_results]
          actual_queries = results[:queries]

          actual_queries.first[:multiplex_start_time]
        end

        # We assert second multiplex began resolving later than the first one. This proves that the thread-local
        # `pre_context` in Tracer, which stores multiplex, parsing start times etc., is reset between Query#result
        # calls.
        assert multiplex_start_times[1] > multiplex_start_times[0]
      end

      test 'extracts metrics in all of the same ways, when a multiplex is executed - regardless if queries are pre-parsed or not' do
        queries = [
          {
            document: GraphQL.parse('query OtherQuery { post(id: "42") { id title } }'),
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
            .context[:simple_extractor_results]

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
          :query_duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :lexing_start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :lexing_duration => SomeNumber.new(at_least: 0),
          :parsing_start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :parsing_duration => SomeNumber.new(at_least: 0),
          :validation_start_time_offset => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :validation_duration => SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :analysis_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :analysis_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
          :multiplex_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
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
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]

        assert_equal_with_diff_on_failure(expected_other_query_queries, other_query_metrics[:queries])
        assert_equal_with_diff_on_failure(expected_other_query_fields, other_query_metrics[:fields])
        assert_equal_with_diff_on_failure(expected_other_query_arguments, other_query_metrics[:arguments])

        assert_equal_with_diff_on_failure(kitchen_sink_expected_queries, kitchen_sink_query_metrics[:queries])
        assert_equal_with_diff_on_failure(kitchen_sink_expected_fields, kitchen_sink_query_metrics[:fields])
        assert_equal_with_diff_on_failure(kitchen_sink_expected_arguments, kitchen_sink_query_metrics[:arguments])
      end

      test "safely skips logging arguments metrics for fields, when the argument value look up fails (possibly because it failed input coercion)" do
        context = { raise_in_prepare: true }
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )

        result = query.result.to_h

        metrics_results = context[:simple_extractor_results]

        actual_queries = metrics_results[:queries]
        actual_fields = metrics_results[:fields]
        actual_arguments = metrics_results[:arguments]

        assert_equal 1, actual_queries.size
        assert actual_fields.size > 1
        assert_equal 8, actual_arguments.size
      end

      test "safely returns static metrics if runtime metrics gathering is interrupted" do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )

        GraphQL::Metrics::Instrumentation.any_instance.expects(:runtime_metrics_interrupted?).returns(true)

        result = query.result.to_h

        metrics_results = context[:simple_extractor_results]

        actual_queries = metrics_results[:queries]
        actual_fields = metrics_results[:fields]
        actual_arguments = metrics_results[:arguments]

        expected_query_metrics = [{:operation_type=>"query", :operation_name=>"PostDetails"}]
        assert_equal expected_query_metrics, actual_queries

        assert actual_fields.size > 1

        expected_field_metric = {
          :field_name=>"id",
          :return_type_name=>"ID",
          :parent_type_name=>"Post",
          :deprecated=>false,
          :path=>["post", "id"] # NOTE that `resolver_timings` and `lazy_resolver_timings` are omitted.
        }
        assert actual_fields.include?(expected_field_metric)
        assert_equal 9, actual_arguments.size
      end

      test 'skips logging for fields and arguments if `skip_field_and_argument_metrics: true` in context' do
        context = {
          GraphQL::Metrics::SKIP_FIELD_AND_ARGUMENT_METRICS => true,
        }

        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

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
        context = { skip_graphql_metrics_analysis: true }
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        expected = {queries: [], fields: [], arguments: [], directives: []}
        assert_equal(expected, results)
      end

      test 'extracts metrics manually via analyze call, with args supplied inline' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          mutation_document_inline_args,
          operation_name: 'PostCreate',
          context: context
        )

        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(shared_expected_arguments_metrics, actual_arguments)
      end

      test 'extracts metrics manually via analyze call with args supplied by variables' do
        context = {}
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
          context: context
        )

        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]
        actual_arguments = results[:arguments]

        assert_equal_with_diff_on_failure(shared_expected_arguments_metrics, actual_arguments)
      end

      test 'fields requested that are not resolved (e.g. id for a post that itself was never resolved) produce no inline field timings' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithFullMetrics,
          '{ post(id: "missing_post") { id } }',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

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
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "title",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "body",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "embeddedTags",
          :argument_type_name => "TagInput",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "handle",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "displayName",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]
      end

      test 'extracts metrics from mutations, input objects' do
        context = {}
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
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

        actual_queries = results[:queries]
        actual_fields = results[:fields]
        actual_arguments = results[:arguments]

        expected_queries = [
          {
            :operation_type=>"mutation",
            :operation_name=>"PostCreate",
            :query_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
            :query_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :lexing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :lexing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :multiplex_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
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
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "title",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "body",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "embeddedTags",
          :argument_type_name => "TagInput",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "PostInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "handle",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
          :parent_input_object_type => "TagInput",
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "displayName",
          :argument_type_name => "String",
          :parent_name => "postCreate",
          :grandparent_type_name => "MutationRoot",
          :grandparent_node_name => "mutation",
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

        query_analyzer SimpleAnalyzer
      end

      test 'works as simple analyzer, gathering static metrics with no runtime data when the analyzer is not used as instrumentation and or a tracer' do
        context = {}
        query = GraphQL::Query.new(
          SchemaWithoutTimingMetrics,
          kitchen_sink_query_document,
          variables: { 'postId': '1', 'titleUpcase': true },
          operation_name: 'PostDetails',
          context: context
        )
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        results = context[:simple_extractor_results]

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
          :parent_name => "title",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "truncate",
          :argument_type_name => "Boolean",
          :parent_name => "body",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Comment",
          :grandparent_node_name => "comments",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_name => "comments",
          :grandparent_type_name => "Comment",
          :grandparent_node_name => "comments",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "id",
          :argument_type_name => "ID",
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => true,
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

        context = {}
        query = GraphQL::Query.new(SchemaWithFullMetrics, query_document, context: context)
        result = query.result.to_h
        refute result['errors'].present?
        assert result['data'].present?

        metrics_results = context[:simple_extractor_results]
        actual_arguments = metrics_results[:arguments]

        expected_arguments = [
          {
            :argument_name=>"post",
            :argument_type_name=>"PostUpdateInput",
            :parent_name=>"postUpdate",
            :grandparent_type_name=>"MutationRoot",
            :grandparent_node_name => "mutation",
            :parent_input_object_type=>nil,
            :default_used=>false,
            :value_is_null=>false,
            :value => SomeArgumentValue.new,
          },
          {
            :argument_name=> "title",
            :argument_type_name=> "String",
            :parent_name=> "postUpdate",
            :grandparent_type_name=> "MutationRoot",
            :grandparent_node_name => "mutation",
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

        context = {}
        query = GraphQL::Query.new(SchemaWithFullMetrics, query_document, context: context)
        result = query.result.to_h

        refute result['errors'].present?
        assert result['data'].present?

        metrics_results = context[:simple_extractor_results]
        actual_arguments = metrics_results[:arguments]

        expected_arguments = [
          {
            :argument_name=>"upvote",
            :argument_type_name=>"PostUpvoteInput",
            :parent_name=>"postUpvote",
            :grandparent_type_name=>"MutationRoot",
            :grandparent_node_name => "mutation",
            :parent_input_object_type=>nil,
            :default_used=>false,
            :value_is_null=>false,
            :value => SomeArgumentValue.new,
          }
        ]

        assert_equal_with_diff_on_failure(expected_arguments, actual_arguments)
      end

      private

      def assert_equal_with_diff_on_failure(expected, actual, sort_by: ->(_x) {} )
        assert_equal(
          expected.sort_by(&sort_by),
          actual.sort_by(&sort_by),
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
            :lexing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :lexing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :parsing_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :validation_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_start_time_offset=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :analysis_duration=>SomeNumber.new(at_least: SMALL_NONZERO_NUMBER),
            :multiplex_start_time=>SomeNumber.new(at_least: REASONABLY_RECENT_UNIX_TIME),
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
          :parent_name => "title",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "truncate",
          :argument_type_name => "Boolean",
          :parent_name => "body",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Comment",
          :grandparent_node_name => "comments",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_name => "comments",
          :grandparent_type_name => "Comment",
          :grandparent_node_name => "comments",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "tags",
          :argument_type_name => "String",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => true,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "ids",
          :argument_type_name => "ID",
          :parent_name => "comments",
          :grandparent_type_name => "Post",
          :grandparent_node_name => "post",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "id",
          :argument_type_name => "ID",
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => false,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }, {
          :argument_name => "locale",
          :argument_type_name => "String",
          :parent_name => "post",
          :grandparent_type_name => "QueryRoot",
          :grandparent_node_name => "query",
          :parent_input_object_type => nil,
          :default_used => true,
          :value_is_null => false,
          :value => SomeArgumentValue.new,
        }]
      end

      def kitchen_sink_query_document
        <<~GRAPHQL
          query PostDetails($postId: ID!, $titleUpcase: Boolean = false, $commentsTags: [String!] = null) {
            post(id: $postId) {
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

      def query_document_with_fragment
        <<~GRAPHQL
          query PostDetails($postId: ID!, $titleUpcase: Boolean = false, $val: Int!) @customDirective(val: $val) {
            post(id: $postId) {
              __typename # Ignored
              ... on Post {
                id @skip(if: true)
                title(upcase: $titleUpcase)
              }
            }
          }
        GRAPHQL
      end

      def query_document_with_directive
        # directive applied on query and field location
        <<~GRAPHQL
          query PostDetails($postId: ID!, $val: Int!) @customDirective(val: $val) {
            post(id: $postId) {
              __typename # Ignored
              id
              title @skip(if: true)
            }
          }
        GRAPHQL
      end

      def mutation_document_with_directive
        <<~GRAPHQL
          mutation PostCreate($postInput: PostInput!) @customDirective(val: 10) {
            postCreate(post: $postInput) {
              post {
                id
              }
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
