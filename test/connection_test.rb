# frozen_string_literal: true

require_relative "test_helper"

class AcpConnectionTest < Minitest::Test
  NOOP = ->(*) {}

  def setup
    @left, @right = ACP.memory_transport_pair
    @connections = []
    @previous_logger = ACP.logger
    ACP.logger = Logger.new(File::NULL)
  end

  def teardown
    @connections.each(&:close)
    ACP.logger = @previous_logger
  end

  def connect(server_handler, client_handler = NOOP, **options)
    server = ACP::Connection.new(server_handler, @right, **options)
    client = ACP::Connection.new(client_handler, @left, **options)
    @connections.push(server, client)
    server.start
    client.start
    [server, client]
  end

  def wait_until(timeout: 2.0)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    until yield
      raise "condition not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.01
    end
  end

  def test_request_response_over_memory_transport
    handler = lambda do |method, params, _is_notification|
      raise ACP::RequestError.method_not_found(method) unless method == "echo"

      { "text" => params["text"] }
    end
    _server, client = connect(handler)

    result = client.send_request("echo", { "text" => "hello" })
    assert_equal "hello", result["text"]
  end

  def test_request_params_are_serialized_from_models
    seen = nil
    handler = lambda do |_method, params, _is_notification|
      seen = params
      ACP::Schema::PromptResponse.new(stop_reason: "end_turn")
    end
    _server, client = connect(handler)

    request = ACP::Schema::PromptRequest.new(
      session_id: "s", prompt: [ACP::Schema::TextContentBlock.new(text: "hi")]
    )
    result = client.send_request("session/prompt", request)
    assert_equal({ "sessionId" => "s", "prompt" => [{ "type" => "text", "text" => "hi" }] }, seen)
    assert_equal({ "stopReason" => "end_turn" }, result)
  end

  def test_notification_does_not_expect_response
    received = []
    handler = ->(method, _params, is_notification) { received << [method, is_notification] }
    _server, client = connect(handler)

    client.send_notification("log", { "level" => "info" })
    wait_until { received.size == 1 }

    assert_equal ["log", true], received.first
  end

  def test_notifications_preserve_order_and_do_not_block_responses
    received = []
    handler = lambda do |method, params, is_notification|
      if is_notification
        sleep 0.05
        received << params["n"]
        nil
      else
        { "method" => method }
      end
    end
    _server, client = connect(handler)

    5.times { |n| client.send_notification("tick", { "n" => n }) }
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = client.send_request("ping")
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    assert_equal "ping", result["method"]
    assert_operator elapsed, :<, 0.2
    wait_until { received.size == 5 }
    assert_equal [0, 1, 2, 3, 4], received
  end

  def test_drain_notifications_waits_for_queued_handlers
    handled = []
    handler = lambda do |_method, params, is_notification|
      next {} unless is_notification

      sleep 0.05
      handled << params["n"]
    end
    server, client = connect(handler)

    3.times { |n| client.send_notification("tick", { "n" => n }) }
    client.send_request("barrier")
    assert_operator handled.size, :<, 3
    assert server.drain_notifications(timeout: 2.0)
    assert_equal [0, 1, 2], handled
  end

  def test_request_error_propagates
    handler = ->(*) { raise ACP::RequestError.invalid_params("details" => "bad") }
    _server, client = connect(handler)

    error = assert_raises(ACP::RequestError) { client.send_request("anything", {}) }
    assert_equal(-32602, error.code)
    assert_equal({ "details" => "bad" }, error.data)
  end

  def test_unexpected_handler_exception_becomes_internal_error
    handler = ->(*) { raise "boom" }
    _server, client = connect(handler)

    error = assert_raises(ACP::RequestError) { client.send_request("anything", {}) }
    assert_equal(-32603, error.code)
    assert_equal "boom", error.data["details"]
  end

  def test_validation_error_becomes_invalid_params
    handler = ->(_method, params, _n) { ACP::Schema::PromptRequest.coerce(params) }
    _server, client = connect(handler)

    error = assert_raises(ACP::RequestError) { client.send_request("session/prompt", { "prompt" => [] }) }
    assert_equal(-32602, error.code)
    assert_match(/sessionId/, error.data["errors"].first["message"])
  end

  def test_unknown_method_returns_method_not_found
    handler = ->(method, *) { raise ACP::RequestError.method_not_found(method) }
    _server, client = connect(handler)

    error = assert_raises(ACP::RequestError) { client.send_request("nope") }
    assert_equal(-32601, error.code)
  end

  def test_non_object_messages_are_ignored_and_connection_keeps_working
    handler = ->(*) { { "ok" => true } }
    _server, client = connect(handler)

    @left.send_message("just a string")
    @left.send_message([1, 2, 3])
    @left.send_message({ "jsonrpc" => "2.0" })
    @left.send_message({ "jsonrpc" => "2.0", "id" => 99, "method" => 42 })

    assert_equal({ "ok" => true }, client.send_request("echo", {}))
  end

  def test_request_with_non_string_method_gets_invalid_request_error
    server = ACP::Connection.new(->(*) { {} }, @right)
    @connections << server
    server.start

    @left.send_message({ "jsonrpc" => "2.0", "id" => "abc", "method" => 42 })
    response = @left.receive_message
    assert_equal "abc", response["id"]
    assert_equal(-32600, response["error"]["code"])
  end

  def test_send_request_has_no_default_timeout_but_honours_explicit_one
    handler = lambda { |*|
      sleep 0.3
      {}
    }
    _server, client = connect(handler)

    error = assert_raises(ACP::TimeoutError) { client.send_request("slow", {}, timeout: 0.05) }
    assert_match(/timed out/, error.message)
    assert_equal({}, client.send_request("slow", {}))
  end

  def test_pending_requests_fail_when_peer_disconnects
    handler = lambda { |*|
      sleep 5
      {}
    }
    server, client = connect(handler)

    waiter = Async do
      client.send_request("never")
    rescue ACP::ConnectionError => e
      e
    end
    sleep 0.05
    server.close

    assert_instance_of ACP::ConnectionError, waiter.wait
  end

  def test_pending_requests_fail_on_local_close
    handler = lambda { |*|
      sleep 5
      {}
    }
    _server, client = connect(handler)

    waiter = Async do
      client.send_request("never")
    rescue ACP::ConnectionError => e
      e
    end
    sleep 0.05
    client.close

    assert_instance_of ACP::ConnectionError, waiter.wait
    assert_raises(ACP::ConnectionError) { client.send_request("after-close") }
  end

  def test_handler_finishing_after_close_does_not_raise
    started = Queue.new
    handler = lambda do |*|
      started << :started
      sleep 0.1
      {}
    end
    server, _client = connect(handler)

    @left.send_message({ "jsonrpc" => "2.0", "id" => 1, "method" => "slow" })
    assert_equal :started, started.pop(timeout: 1.0)
    worker = server.instance_variable_get(:@workers).first
    refute_nil worker
    server.close

    assert ACP::Wait.join(worker, 1.0)
    assert_empty server.instance_variable_get(:@workers)
  end

  def test_in_flight_handlers_are_cancelled_after_grace_period
    handler = lambda { |*|
      sleep 5
      {}
    }
    server, _client = connect(handler, worker_grace: 0.05)

    @left.send_message({ "jsonrpc" => "2.0", "id" => 1, "method" => "slow" })
    wait_until { !server.instance_variable_get(:@workers).empty? }
    worker = server.instance_variable_get(:@workers).first

    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.close
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 1.0
    ACP::Wait.join(worker, 1.0)
    refute ACP::Wait.alive?(worker)
  end

  def test_workers_are_pruned_after_completion
    handler = ->(*) { {} }
    server, client = connect(handler)

    50.times { |i| client.send_request("echo", { "i" => i }) }
    wait_until { server.instance_variable_get(:@workers).empty? }
  end

  def test_observers_see_incoming_and_outgoing_messages
    handler = ->(*) { { "ok" => true } }
    _server, client = connect(handler)
    events = []
    client.add_observer { |event| events << [event.direction, event.message["method"] || event.message["id"]] }

    client.send_request("echo", {})
    client.send_notification("note")

    assert_includes events, [:outgoing, "echo"]
    assert_includes events, [:incoming, 0]
    assert_includes events, [:outgoing, "note"]
  end

  def test_start_and_join
    server, client = connect(->(*) {})
    client.close
    server.close

    assert server.join(2)
    assert client.join(2)
  end

  def test_send_request_yields_to_other_async_fibers
    require "async"

    handler = lambda do |method, params, _is_notification|
      raise ACP::RequestError.method_not_found(method) unless method == "echo"

      sleep 0.2
      { "text" => params["text"] }
    end

    Sync do
      left, right = ACP.memory_transport_pair
      server = ACP::Connection.new(handler, right)
      client = ACP::Connection.new(NOOP, left)
      server.start
      client.start

      ticks = 0
      ticker = Async do
        40.times do
          ticks += 1
          sleep 0.01
        end
      end

      result = client.send_request("echo", { "text" => "hello" })
      ticker.wait

      assert_equal "hello", result["text"]
      assert_operator ticks, :>=, 5

      client.close
      server.close
    end
  end

  def test_async_notifications_and_timeouts
    require "async"

    received = []
    handler = lambda do |_method, params, is_notification|
      if is_notification
        received << params["n"]
        nil
      else
        sleep 0.3
        {}
      end
    end

    Sync do
      left, right = ACP.memory_transport_pair
      server = ACP::Connection.new(handler, right)
      client = ACP::Connection.new(NOOP, left)
      server.start
      client.start

      3.times { |n| client.send_notification("tick", { "n" => n }) }
      assert server.drain_notifications(timeout: 1.0)
      assert_equal [0, 1, 2], received
      assert_raises(ACP::TimeoutError) { client.send_request("slow", {}, timeout: 0.05) }

      client.close
      server.close
    end
  end
end
