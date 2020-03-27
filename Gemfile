source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

# Specify your gem's dependencies in graphql_metrics.gemspec

gem 'graphql', github: 'rmosolgo/graphql-ruby', branch: 'query-args-default-values' # TODO remove once fix is in 1.10

gemspec

group :deployment do
  gem 'rake'
end
