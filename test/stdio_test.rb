# frozen_string_literal: true

require_relative "test_helper"

class AcpStdioTest < Minitest::Test
  S = ACP::Schema
  AGENT_SCRIPT = File.expand_path("fixtures/echo_agent.rb", __dir__)

  class CollectingClient
    attr_reader :updates

    def initialize
      @updates = []
    end

    def session_update(notification)
      @updates << notification
    end
  end

  def setup
    @process = nil
    @previous_logger = ACP.logger
    @log = StringIO.new
    ACP.logger = Logger.new(@log)
  end

  def teardown
    @process&.close(timeout: 1.0)
    ACP.logger = @previous_logger
  end

  def spawn(**options)
    @process = ACP::Stdio.spawn_agent(RbConfig.ruby, AGENT_SCRIPT, **options)
  end

  def test_default_environment_includes_path
    env = ACP::Stdio.default_environment
    assert env.key?("PATH")
  end

  def test_spawn_without_cwd_and_talk_over_stdio_with_stderr_noise
    process = spawn
    client_handler = CollectingClient.new
    client = process.connect(client_handler)

    init = client.initialize_agent(client_info: S::Implementation.new(name: "test-client", version: "1"))
    assert_equal "echo-agent", init.agent_info.name

    session = client.new_session(cwd: Dir.pwd)
    assert_match(/\Aecho-\d+\z/, session.session_id)

    response = client.prompt(session_id: session.session_id, prompt: [S::TextContentBlock.new(text: "abc")])
    assert_equal "end_turn", response.stop_reason
    assert_equal 1, client_handler.updates.size
    assert_equal "cba", client_handler.updates.first.update.content.text

    client.close
    status = process.close(timeout: 2.0)
    refute process.alive?
    refute_nil status
    assert_match(/echo-agent: prompt "abc"/, @log.string)
  end

  def test_spawn_with_cwd_and_extra_env
    Dir.mktmpdir("acp-cwd") do |dir|
      process = spawn(cwd: dir, env: { "ECHO_AGENT_FLAG" => "1" })
      client = process.connect(Object.new)
      result = client.ext_method("where", {})
      assert_equal File.realpath(dir), File.realpath(result["cwd"])
      client.close
    end
  end

  def test_pending_request_fails_when_agent_process_dies
    process = spawn
    client = process.connect(Object.new)
    client.initialize_agent

    waiter = Async do
      client.ext_method("sleep", { "seconds" => 10 })
    rescue ACP::Error => e
      e
    end
    sleep 0.1
    process.kill("KILL")

    assert_kind_of ACP::ConnectionError, waiter.wait
    assert client.join(2.0)
  end
end
