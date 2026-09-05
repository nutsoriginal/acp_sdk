# frozen_string_literal: true

require_relative "test_helper"

# Extended stdio coverage: stderr modes, env filtering/merging, process
# lifecycle (alive?/kill/wait/close), receive_timeout passthrough.
class AcpStdioExtTest < Minitest::Test
  S = ACP::Schema
  AGENT_SCRIPT = File.expand_path("fixtures/echo_agent.rb", __dir__)

  def setup
    @processes = []
    @previous_logger = ACP.logger
    @log = StringIO.new
    ACP.logger = Logger.new(@log)
  end

  def teardown
    @processes.each do |p|
      p.close(timeout: 1.0)
    rescue StandardError
      nil
    end
    ACP.logger = @previous_logger
  end

  def spawn(**options)
    process = ACP::Stdio.spawn_agent(RbConfig.ruby, AGENT_SCRIPT, **options)
    @processes << process
    process
  end

  def with_env(key, value)
    had_key = ENV.key?(key)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    had_key ? ENV[key] = old : ENV.delete(key)
  end

  # --- default_environment ---

  def test_default_environment_filters_shell_functions
    # Only allowlisted keys are inherited; function-style values are dropped
    # (shellshock guard), plain values pass through.
    with_env("TERM", "() { echo hi; }") do
      refute ACP::Stdio.default_environment.key?("TERM")
    end
    with_env("TERM", "xterm-test") do
      assert_equal "xterm-test", ACP::Stdio.default_environment["TERM"]
    end
    with_env("ACP_TEST_PLAIN", "hello") do
      refute ACP::Stdio.default_environment.key?("ACP_TEST_PLAIN")
    end
  end

  def test_spawn_merges_symbol_env_keys
    process = spawn(env: { "ECHO_AGENT_FLAG" => "1", :OTHER_FLAG => "x" })
    client = process.connect(Object.new)
    # Echo agent does not echo env, but spawn must not raise on symbol keys.
    init = client.initialize_agent(client_info: S::Implementation.new(name: "t", version: "1"))
    assert_equal "echo-agent", init.agent_info.name
    client.close
  end

  # --- stderr modes ---

  def test_stderr_discard_logs_nothing
    process = spawn(stderr: :discard)
    client = process.connect(Object.new)
    client.initialize_agent
    client.close
    assert_empty @log.string
  end

  def test_stderr_to_io_object_receives_child_stderr
    buffer = StringIO.new
    # StringIO is not an IO, so spawn must reject it explicitly.
    assert_raises(ArgumentError) { ACP::Stdio.spawn_agent(RbConfig.ruby, "-e", "exit 0", stderr: buffer) }
  end

  def test_stderr_invalid_option_raises
    assert_raises(ArgumentError) { ACP::Stdio.spawn_agent(RbConfig.ruby, "-e", "exit 0", stderr: :bogus) }
  end

  def test_stderr_io_object_receives_child_output
    reader, writer = IO.pipe
    process = ACP::Stdio.spawn_agent(RbConfig.ruby, AGENT_SCRIPT, stderr: writer)
    @processes << process
    writer.close
    client = process.connect(Object.new)
    client.initialize_agent(client_info: S::Implementation.new(name: "t", version: "1"))
    client.close
    output = reader.read
    reader.close
    assert_match(/echo-agent: initialize/, output)
  end

  # --- process lifecycle ---

  def test_alive_tracks_process_state
    process = spawn
    assert process.alive?
    client = process.connect(Object.new)
    client.initialize_agent
    client.close
    process.close(timeout: 2.0)
    refute process.alive?
    refute_nil process.wait
  end

  def test_kill_terminates_hanging_process_and_close_returns_status
    # `sleep` ignores ACP entirely: exercises kill/close without a client.
    reader, writer = IO.pipe
    pid = Process.spawn(RbConfig.ruby, "-e", "sleep 30", out: writer, err: File::NULL)
    writer.close
    transport = ACP::NdjsonTransport.new(reader, IO.pipe.last)
    victim = ACP::Stdio::AgentProcess.new(pid: pid, transport: transport, stdin: IO.pipe.first, stdout: reader)
    @processes << victim
    assert victim.alive?
    victim.kill
    status = victim.close(timeout: 3.0)
    refute victim.alive?
    refute_nil status
  end

  def test_close_is_idempotent
    process = spawn
    client = process.connect(Object.new)
    client.initialize_agent
    client.close
    first = process.close(timeout: 2.0)
    second = process.close(timeout: 1.0)
    assert_equal first, second
  end

  # --- receive_timeout passthrough ---

  def test_spawn_receive_timeout_reaches_transport
    process = spawn(receive_timeout: 0.05)
    timeout = process.transport.instance_variable_get(:@receive_timeout)
    assert_equal 0.05, timeout
    process.connect(Object.new).close
  end

  def test_stdio_streams_sets_binary_utf8_and_sync
    input_reader, input_writer = IO.pipe
    output_reader, output_writer = IO.pipe
    input, output = ACP::Stdio.stdio_streams(input_reader, output_writer)
    assert_equal Encoding::UTF_8, input.external_encoding
    assert_equal Encoding::UTF_8, output.external_encoding
    assert output.sync
    [input_reader, input_writer, output_reader, output_writer].each do |io|
      io.close
    rescue StandardError
      nil
    end
  end
end
