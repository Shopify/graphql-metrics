require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]

  # TODO: We should remove this line. See `puts` line below.
  t.warning = false

  puts "Reminder: Remove `t.warning = false` in Rakefile once graphql-ruby fixes all instances of"\
    "`warning: instance variable @<ivar> not initialized` and `mismatched indentations`"
end

task :default => :test
