# frozen_string_literal: true

require "json"
require "logger"
require "stringio"
require "tmpdir"
require "async"

begin
  raise LoadError, "coverage disabled" if ENV["COVERAGE"] == "false"

  require "simplecov"
  SimpleCov.start do
    enable_coverage :line
    minimum_coverage 90
  end
  # `skip` replaced `add_filter` in SimpleCov 1.x; keep working without it.
  if SimpleCov.respond_to?(:skip)
    SimpleCov.skip "/test/"
    SimpleCov.skip "/scripts/"
  else
    SimpleCov.add_filter "/test/"
    SimpleCov.add_filter "/scripts/"
  end
rescue LoadError
  # SimpleCov is optional for local runs; CI installs it via the Gemfile.
end

require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "acp_sdk_async"

module AcpTest
  def run
    result = nil
    Sync { result = super }
    result
  end
end

Minitest::Test.prepend(AcpTest)
