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
