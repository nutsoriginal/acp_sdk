# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.test_files = FileList["test/**/*_test.rb"]
  t.warning = false
end

desc "Regenerate lib/acp/schema.rb and lib/acp/meta.rb from schema/*.json"
task :gen_schema do
  require_relative "scripts/gen_schema"
  ACP::SchemaGenerator.run
  puts "Generated #{ACP::SchemaGenerator::OUT_SCHEMA} and #{ACP::SchemaGenerator::OUT_META}"
end

task default: :test
