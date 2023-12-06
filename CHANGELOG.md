5.0.8
-----
- [76](https://github.com/Shopify/graphql-metrics/pull/76) Reduce object allocations

5.0.7
-----
- [75](https://github.com/Shopify/graphql-metrics/pull/75) Trace: capture path before yielding

5.0.6
-----
- [74](https://github.com/Shopify/graphql-metrics/pull/74) Fix skip_tracing compatibility with new Tracing API

5.0.5
-----
- [73](https://github.com/Shopify/graphql-metrics/pull/73) Fix calls to other traces.

5.0.4
-----
- [66](https://github.com/Shopify/graphql-metrics/pull/66) Support graphql-ruby's new tracing API (backwards compatible)
- [71](https://github.com/Shopify/graphql-metrics/pull/71) Fix handling of inline fragment without a parent type.

5.0.3
-----
- [69](https://github.com/Shopify/graphql-metrics/pull/69) Loosen concurrent-ruby dependency

5.0.2
-----
- [63](https://github.com/Shopify/graphql-metrics/pull/67) Reset `lex` pre-context metrics on `analyze_multiplex`.
5.0.1
-----
- [63](https://github.com/Shopify/graphql-metrics/pull/63) Eliminate `TimedResult` objects for `trace_field`.
5.0.0
-----
- [50](https://github.com/Shopify/graphql-metrics/pull/50) Capture metrics for directives and their arguments.
4.1.0
-----
- [42](https://github.com/Shopify/graphql-metrics/pull/42) Capture timing of the `lex` phase.

4.0.6
-----
- [35](https://github.com/Shopify/graphql-metrics/pull/35) Fix query start time, start time offset bugs.

4.0.5
-----
- [34](https://github.com/Shopify/graphql-metrics/pull/34) Fix default of pre-parsed query `parsing_duration` to be Float (`0.0`) rather than Integer (`0`).

4.0.4
-----
- [33](https://github.com/Shopify/graphql-metrics/pull/33) Setup tracing using lex or execute_multiplex tracer events.

4.0.3
-----
- [32](https://github.com/Shopify/graphql-metrics/pull/32) Split validate and analyze_query tracer events (encompasses #30).
- [30](https://github.com/Shopify/graphql-metrics/pull/30) Handle queries that have already been parsed (thank you @jturkel).
- [29](https://github.com/Shopify/graphql-metrics/pull/29) Remove runtime dependency on activesupport (thank you @jturkel).

4.0.2
-----
- [25](https://github.com/Shopify/graphql-metrics/pull/25) Safely handle interrupted runtime metrics.

4.0.1
-----
- [24](https://github.com/Shopify/graphql-metrics/pull/24) Safely call `arguments_for` to handle arguments which may
raise `ExecutionError`s in their `prepare` methods.

4.0.0
-----
- [23](https://github.com/Shopify/graphql-metrics/pull/23) graphql-ruby 1.10.8+ compatibility

3.0.3
-----

- [#22](https://github.com/Shopify/graphql-metrics/pull/22) Optimization: use hash assignment over merge

3.0.2
-----

- [#21](https://github.com/Shopify/graphql-metrics/pull/21) Optimize empty document check

3.0.1
-----

Expand the range of graphql-ruby versions this gem is compatible with.

3.0.0
-----

A complete re-write of the gem.

Just about everything in the 2.0.0 public interface breaks, but everything gets substantially better, with more metrics
extracted, more consistent naming and structures, and it all runs faster too! 🎉

The core analyzer (which your app should subclass) is now a `GraphQL::Analysis::AST::Analyzer`, and the tracer and
instrumentation for timings metrics are now fully separate classes.

2.0.1
-----

Fixes cases where instances of `GraphQLMetrics::Instrumentation` are passed to `Schema#new`, i.e. via `Schema.redefine`
(https://github.com/Shopify/graphql-metrics/commit/6624dcd0aa04006f092b850752bb05d3da688745#diff-d64de6d4fb3a1d05c273e19469c9852aR439)

2.0.0
-----

2.0.0 contains a breaking change.

See https://github.com/Shopify/graphql-metrics#usage

* `GraphQLMetrics::Extractor` was renamed `GraphQLMetrics::Instrumentation` <- Use the latter to migrate away from the
  breaking change.
* `GraphQLMetrics::Extractor` was then re-introduced in order to support ad hoc static query metrics extraction,
  without using subclasses as runtime instrumentation.


1.0.1 to 1.1.5
-----

* Minor bug fixes

1.0.0
-----

* Initialize release! 🎉
