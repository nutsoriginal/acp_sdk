# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "rbconfig"

# Runs the bundled examples as subprocesses and checks their transcript.
class AcpExamplesTest < Minitest::Test
  DUET = File.expand_path("../examples/duet.rb", __dir__)
  ROOT = File.expand_path("..", __dir__)

  def run_duet(*args)
    Open3.capture2e(RbConfig.ruby, "-Ilib", DUET, *args, chdir: ROOT)
  end

  def test_duet_explicit_messages
    out, status = run_duet("ping", "pong")
    assert status.success?, out
    assert_includes out, "> ping\n| Agent: Client sent:\n| Agent: ping\n"
    assert_includes out, "> pong\n| Agent: Client sent:\n| Agent: pong\n"
  end

  def test_duet_default_message
    out, status = run_duet
    assert status.success?, out
    assert_includes out, "> Hello, agent!\n"
    assert_includes out, "| Agent: Hello, agent!\n"
  end
end
