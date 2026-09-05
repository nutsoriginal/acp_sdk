# frozen_string_literal: true

require_relative "test_helper"

class AcpFixesTest < Minitest::Test
  S = ACP::Schema
  NOOP = ->(*) {}

  def setup
    @previous_logger = ACP.logger
    ACP.logger = Logger.new(File::NULL)
    @connections = []
    @transports = []
  end

  def teardown
    @connections.each(&:close)
    @transports.each do |t|
      t.close
    rescue StandardError
      nil
    end
    ACP.logger = @previous_logger
  end

  def track(conn)
    @connections << conn
    conn
  end

  def memory_pair
    left, right = ACP.memory_transport_pair
    @transports.push(left, right)
    [left, right]
  end

  # --- MemoryTransport: peer-only EOF + drain queued ---

  def test_memory_close_drains_queued_before_eof
    left, right = memory_pair
    left.send_message({ "n" => 1 })
    left.send_message({ "n" => 2 })
    left.close

    assert_equal({ "n" => 1 }, right.receive_message)
    assert_equal({ "n" => 2 }, right.receive_message)
    assert_nil right.receive_message
    # Local side returns nil via closed?+empty fast path, does not hang.
    assert_nil left.receive_message
    assert_raises(ACP::ConnectionError) { left.send_message({}) }
  end

  def test_memory_close_is_idempotent
    left, right = memory_pair
    left.close
    left.close
    assert_nil right.receive_message
  end

  # --- Ndjson receive_timeout covers partial lines (TOCTOU) ---

  def test_ndjson_timeout_on_partial_line_without_newline
    reader, writer = IO.pipe
    transport = ACP::NdjsonTransport.new(reader, writer, receive_timeout: 0.05)
    @transports << transport
    writer.write("partial without newline")
    assert_raises(ACP::TimeoutError) { transport.receive_message }
    transport.close
  end

  def test_ndjson_no_timeout_returns_full_line
    reader, writer = IO.pipe
    transport = ACP::NdjsonTransport.new(reader, writer, receive_timeout: 1.0)
    @transports << transport
    writer.write("{\"ok\":true}\n")
    assert_equal({ "ok" => true }, transport.receive_message)
    transport.close
  end

  # --- Connection close idempotency (ClosedQueueError regression) ---

  def test_connection_close_twice_does_not_raise
    left, right = memory_pair
    server = track(ACP::Connection.new(NOOP, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start
    client.close
    client.close
    server.close
    assert client.join(2)
    assert server.join(2)
  end

  # --- Observers: deepcopy isolation ---

  def test_observer_mutation_does_not_change_wire_payload
    left, right = memory_pair
    seen_by_peer = nil
    server_handler = lambda do |_method, params, _is_notif|
      seen_by_peer = params
      {}
    end
    server = track(ACP::Connection.new(server_handler, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    client.add_observer do |event|
      event.message["params"] = { "hacked" => true } if event.direction == :outgoing
    end

    client.send_request("echo", { "text" => "original" })
    assert_equal({ "text" => "original" }, seen_by_peer)
  end

  def test_failed_send_does_not_notify_outgoing
    left, _right = memory_pair
    client = track(ACP::Connection.new(NOOP, left))
    client.start
    events = []
    client.add_observer { |e| events << e.direction if e.direction == :outgoing }
    left.close
    assert_raises(ACP::ConnectionError) { client.send_request("echo", {}) }
    assert_empty events
  end

  def test_incoming_observer_sees_copy
    left, right = memory_pair
    server = track(ACP::Connection.new(->(*) { {} }, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    mutated = nil
    client.add_observer do |event|
      if event.direction == :incoming
        event.message["result"] = "hacked"
        mutated = true
      end
    end
    # Server handler returns real value; observer mutates its own copy only.
    result = client.send_request("echo", {})
    assert mutated
    assert_equal({}, result)
  end

  # --- handle_response: result-first, empty -> nil, unknown id ---

  def test_response_with_both_result_and_error_prefers_result
    left, right = memory_pair
    # Slow handler keeps the request pending so we can inject a raw response.
    server = track(ACP::Connection.new(lambda { |*|
      sleep 5
      {}
    }, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    waiter = Async { client.send_request("echo", {}) }
    sleep 0.05
    pending_id = client.instance_variable_get(:@pending).keys.first
    refute_nil pending_id
    right.send_message({ "jsonrpc" => "2.0", "id" => pending_id, "result" => { "ok" => true }, "error" => { "code" => -32603, "message" => "boom" } })
    assert_equal({ "ok" => true }, waiter.wait)
  end

  def test_response_without_result_nor_error_resolves_nil
    left, right = memory_pair
    server = track(ACP::Connection.new(lambda { |*|
      sleep 5
      {}
    }, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    waiter = Async { client.send_request("echo", {}) }
    sleep 0.05
    pending_id = client.instance_variable_get(:@pending).keys.first
    right.send_message({ "jsonrpc" => "2.0", "id" => pending_id })
    assert_nil waiter.wait
  end

  def test_response_for_unknown_id_is_ignored
    left, right = memory_pair
    server = track(ACP::Connection.new(->(*) { { "ok" => true } }, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    left.send_message({ "jsonrpc" => "2.0", "id" => 9999, "result" => {} })
    sleep 0.05
    assert_equal({ "ok" => true }, client.send_request("echo", {}))
  end

  # --- Parallel close ---

  def test_close_with_multiple_slow_handlers_is_parallel_not_sequential
    left, right = memory_pair
    handler = lambda { |*|
      sleep 5
      {}
    }
    server = track(ACP::Connection.new(handler, right, worker_grace: 0.05))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    3.times { |i| left.send_message({ "jsonrpc" => "2.0", "id" => i, "method" => "slow" }) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2.0
    sleep 0.05 until server.instance_variable_get(:@workers).size >= 3 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
    assert_equal 3, server.instance_variable_get(:@workers).size

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.close
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    # Sequential 3*0.05 grace + overhead would still be <0.5s, but sequential
    # 3*0.5 default would be >1s. With grace 0.05 parallel must be well under 1s.
    assert_operator elapsed, :<, 1.0
  end

  def test_drain_after_close_returns_true_without_hanging
    left, right = memory_pair
    server = track(ACP::Connection.new(NOOP, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start
    server.close
    assert server.drain_notifications(timeout: 0.1)
  end

  # --- Router: nil params must fail validation ---

  def test_router_nil_params_raises_validation_not_empty_hash
    router = ACP::Router.new
    target = Object.new
    def target.prompt(req) = req
    router.route_request("session/prompt", S::PromptRequest, target, :prompt)

    assert_raises(ACP::Schema::ValidationError) { router.call("session/prompt", nil, false) }
  end

  def test_router_extension_nil_params_becomes_empty_hash
    router = ACP::Router.new
    router.on_extension_request { |name, params| [name, params] }
    assert_equal(["custom", {}], router.call("_custom", nil, false))
  end

  # --- Schema: required in initialize ---

  def test_initialize_missing_required_raises
    assert_raises(ACP::Schema::ValidationError) { S::PromptRequest.new(prompt: []) }
    assert_raises(ACP::Schema::ValidationError) { S::PromptRequest.new(session_id: nil, prompt: []) }
    # Valid construction still works.
    req = S::PromptRequest.new(session_id: "s", prompt: [])
    assert_equal "s", req.session_id
  end

  def test_initialize_default_on_error_uses_default_instead_of_raising
    # kind=bogus is invalid enum but has default_on_error -> becomes nil, no raise.
    update = S::ToolCallUpdate.new(tool_call_id: "c1", kind: "bogus")
    assert_nil update.kind
  end

  def test_initialize_const_mismatch_raises
    assert_raises(ACP::Schema::ValidationError) do
      S::ToolCallStart.new(tool_call_id: "c", title: "t", session_update: "wrong")
    end
  end

  def test_reserved_tags_are_rejected
    assert_raises(ACP::Schema::ValidationError) { S::OtherElicitationResponse.coerce({ "action" => "accept" }) }
    assert_raises(ACP::Schema::ValidationError) { S::OtherElicitationResponse.new(action: "decline") }
    assert_raises(ACP::Schema::ValidationError) do
      S::CreateOtherSessionElicitationRequest.coerce({ "message" => "m", "mode" => "form", "sessionId" => "s" })
    end
    assert_raises(ACP::Schema::ValidationError) do
      S::ElicitationOtherPropertySchema.coerce({ "type" => "string" })
    end
    assert_raises(ACP::Schema::ValidationError) { S::OtherMultiSelectItems.coerce({ "type" => "string" }) }
    # Non-reserved still works.
    other = S::OtherElicitationResponse.coerce({ "action" => "weird" })
    assert_equal "weird", other.action
  end

  # --- Wait::Promise settled covers both resolve and reject ---

  def test_promise_settled_after_resolve_and_reject
    p1 = ACP::Wait::Promise.new
    refute p1.settled?
    p1.resolve(1)
    assert p1.settled?

    p2 = ACP::Wait::Promise.new
    p2.reject(StandardError.new("x"))
    assert p2.settled?
  end

  # --- Client alias ---

  def test_set_config_option_alias
    assert_equal(
      ACP::Client::Connection.instance_method(:set_session_config_option),
      ACP::Client::Connection.instance_method(:set_config_option)
    )
  end

  def test_set_config_option_alias_end_to_end
    left, right = memory_pair
    seen = nil
    agent_handler = lambda do |method, params, _is_notif|
      seen = [method, params]
      { "configOptions" => [] }
    end
    server = track(ACP::Connection.new(agent_handler, right))
    client_handler = Object.new
    client = ACP::Client::Connection.new(client_handler, left)
    track(client.conn)
    server.start
    client.start

    client.set_config_option(session_id: "s", config_id: "c", value: true)
    assert_equal "session/set_config_option", seen[0]
    assert_equal true, seen[1]["value"]
  end

  def test_send_request_timeout_cleans_pending
    left, right = memory_pair
    server = track(ACP::Connection.new(lambda { |*|
      sleep 5
      {}
    }, right))
    client = track(ACP::Connection.new(NOOP, left))
    server.start
    client.start

    assert_raises(ACP::TimeoutError) { client.send_request("slow", {}, timeout: 0.05) }
    assert_empty client.instance_variable_get(:@pending)
  end

  # --- Agent request_optional returns nil on null ---

  def test_agent_optional_helpers_return_nil_on_null
    left, right = memory_pair
    # Client side returns null for optional terminals (default nil).
    client_router = ACP::Router.new
    client_router.route_request("terminal/create", S::CreateTerminalRequest, Object.new, :nope, optional: true)
    client_router.route_request("terminal/release", S::ReleaseTerminalRequest, Object.new, :nope, optional: true, default_result: {}, normalize: true)
    server_conn = track(ACP::Connection.new(client_router.method(:call), right))
    agent_conn = ACP::Agent::Connection.new(Object.new, left)
    track(agent_conn.conn)
    server_conn.start
    agent_conn.start

    # release returns {} (default) -> empty model, not nil.
    release = agent_conn.release_terminal(session_id: "s", terminal_id: "t")
    assert_instance_of S::ReleaseTerminalResponse, release

    # Simulate explicit null response for write_text_file -> nil.
    null_router = ACP::Router.new
    null_router.add_route(ACP::Route.new(method: "fs/write_text_file", handler: ->(*) { nil }, kind: :request))
    left2, right2 = memory_pair
    s2 = track(ACP::Connection.new(null_router.method(:call), right2))
    a2 = ACP::Agent::Connection.new(Object.new, left2)
    track(a2.conn)
    s2.start
    a2.start
    assert_nil a2.write_text_file(session_id: "s", path: "p", content: "c")
  end

  def test_create_elicitation_message_mode_form
    left, right = memory_pair
    seen = nil
    server_handler = lambda do |method, params, _is_notif|
      seen = [method, params]
      { "action" => "decline" }
    end
    server = track(ACP::Connection.new(server_handler, right))
    agent_conn = ACP::Agent::Connection.new(Object.new, left)
    track(agent_conn.conn)
    server.start
    agent_conn.start

    mode = S::ElicitationFormSessionMode.new(
      requested_schema: S::ElicitationSchema.new(properties: {}, required: []),
      session_id: "s",
      tool_call_id: "c"
    )
    response = agent_conn.create_elicitation(message: "Fill?", mode: mode)
    assert_instance_of S::DeclineElicitationResponse, response
    method, params = seen
    assert_equal "elicitation/create", method
    assert_equal "Fill?", params["message"]
    assert_equal "form", params["mode"]
    assert_equal "s", params["sessionId"]
  end

  def test_create_elicitation_legacy_request_hash_still_works
    left, right = memory_pair
    seen = nil
    server_handler = lambda do |_method, params, _is_notif|
      seen = params
      { "action" => "weird" }
    end
    server = track(ACP::Connection.new(server_handler, right))
    agent_conn = ACP::Agent::Connection.new(Object.new, left)
    track(agent_conn.conn)
    server.start
    agent_conn.start

    response = agent_conn.create_elicitation({ "message" => "m", "mode" => "other-mode", "sessionId" => "s" })
    assert_instance_of S::OtherElicitationResponse, response
    assert_equal "other-mode", seen["mode"]
  end

  def test_create_elicitation_message_mode_url
    left, right = memory_pair
    seen = nil
    server_handler = lambda do |method, params, _is_notif|
      seen = [method, params]
      { "action" => "cancel" }
    end
    server = track(ACP::Connection.new(server_handler, right))
    agent_conn = ACP::Agent::Connection.new(Object.new, left)
    track(agent_conn.conn)
    server.start
    agent_conn.start

    mode = S::ElicitationUrlRequestMode.new(
      elicitation_id: "e1",
      url: "https://example.com/auth",
      request_id: "r1"
    )
    response = agent_conn.create_elicitation(message: "Login?", mode: mode)
    assert_instance_of S::CancelElicitationResponse, response
    _method, params = seen
    assert_equal "url", params["mode"]
    assert_equal "https://example.com/auth", params["url"]
  end
end
