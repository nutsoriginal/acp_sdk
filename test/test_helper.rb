# frozen_string_literal: true

require "json"
require "logger"
require "stringio"
require "tmpdir"
require "async"
require "minitest/autorun"

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "acp_sdk"

module AcpTest
  def run
    result = nil
    Sync { result = super }
    result
  end
end

Minitest::Test.prepend(AcpTest)
