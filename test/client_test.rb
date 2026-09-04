# frozen_string_literal: true

require_relative "test_helper"

class AcpClientTest < Minitest::Test
  S = ACP::Schema

  class FakeAgent
    attr_reader :requests, :cancelled, :ext_calls, :connection

    def initialize
      @requests = []
      @cancelled = []
      @ext_calls = []
    end

    def on_connect(connection)
      @connection = connection
    end

    def initialize_acp(request)
      @requests << request
      S::InitializeResponse.new(
        protocol_version: request.protocol_version,
        agent_capabilities: S::AgentCapabilities.new(load_session: true),
        agent_info: S::Implementation.new(name: "fake", version: "1.0")
      )
    end

    def new_session(request)
      @requests << request
      S::NewSessionResponse.new(session_id: "sess_1", modes: nil)
    end

    def prompt(request)
      @requests << request
      @connection.session_update(
        session_id: request.session_id,
        update: S::AgentThoughtChunk.new(content: S::TextContentBlock.new(text: "thinking"))
      )
      @connection.session_update(
        session_id: request.session_id,
        update: S::ToolCallStart.new(tool_call_id: "call_1", title: "Read file", kind: "read", status: "pending")
      )
      permission = @connection.request_permission(
        session_id: request.session_id,
        tool_call: S::ToolCallUpdate.new(tool_call_id: "call_1", status: "in_progress"),
        options: [S::PermissionOption.new(option_id: "allow", name: "Allow", kind: "allow_once")]
      )
      @connection.session_update(
        session_id: request.session_id,
        update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "outcome=#{permission.outcome.class.name.split('::').last}"))
      )
      S::PromptResponse.new(stop_reason: "end_turn", usage: S::Usage.new(total_tokens: 3, input_tokens: 1, output_tokens: 2))
    end

    def cancel(notification)
      @cancelled << notification.session_id
    end

    def set_session_config_option(request)
      @requests << request
      S::SetSessionConfigOptionResponse.new(config_options: [])
    end

    def ext_method(name, params)
      @ext_calls << [name, params]
      { "echo" => params }
    end
  end

  class FakeClient
    attr_reader :updates, :permission_requests

    def initialize
      @updates = []
      @permission_requests = []
    end

    def session_update(notification)
      sleep 0.02
      @updates << notification
    end

    def request_permission(request)
      @permission_requests << request
      S::RequestPermissionResponse.new(outcome: S::AllowedOutcome.new(option_id: request.options.first.option_id))
    end

    def read_text_file(request)
      S::ReadTextFileResponse.new(content: "content of #{request.path}")
    end
  end

  def setup
    @client_transport, @agent_transport = ACP.memory_transport_pair
    @agent = FakeAgent.new
    @client_handler = FakeClient.new
    @agent_conn = ACP::Agent::Connection.new(@agent, @agent_transport)
    @client = ACP::Client::Connection.new(@client_handler, @client_transport)
    @agent_conn.start
    @client.start
  end

  def teardown
    @client.close
    @agent_conn.close
  end

  def test_full_prompt_turn_with_typed_models
    init = @client.initialize_agent(
      client_capabilities: S::ClientCapabilities.new(fs: S::FileSystemCapabilities.new(read_text_file: true)),
      client_info: S::Implementation.new(name: "daedalus", version: "0.1")
    )
    assert_instance_of S::InitializeResponse, init
    assert_equal 1, init.protocol_version
    assert_equal "fake", init.agent_info.name
    assert init.agent_capabilities.load_session

    init_request = @agent.requests.first
    assert_instance_of S::InitializeRequest, init_request
    assert_equal true, init_request.client_capabilities.fs.read_text_file
    assert_equal "daedalus", init_request.client_info.name

    session = @client.new_session(cwd: "/tmp")
    assert_equal "sess_1", session.session_id
    assert_equal [], @agent.requests.last.mcp_servers

    response = @client.prompt(session_id: "sess_1", prompt: [S::TextContentBlock.new(text: "hi")])
    assert_instance_of S::PromptResponse, response
    assert_equal "end_turn", response.stop_reason
    assert_equal 3, response.usage.total_tokens

    assert_equal 3, @client_handler.updates.size
    kinds = @client_handler.updates.map { |n| n.update.class }
    assert_equal [S::AgentThoughtChunk, S::ToolCallStart, S::AgentMessageChunk], kinds
    assert_equal "outcome=AllowedOutcome", @client_handler.updates.last.update.content.text
    assert_equal "read", @client_handler.updates[1].update.kind

    permission = @client_handler.permission_requests.first
    assert_instance_of S::RequestPermissionRequest, permission
    assert_equal "call_1", permission.tool_call.tool_call_id
  end

  def test_agent_can_call_client_methods
    @client.initialize_agent
    response = @agent_conn.read_text_file(session_id: "sess_1", path: "/etc/hosts")
    assert_instance_of S::ReadTextFileResponse, response
    assert_equal "content of /etc/hosts", response.content
  end

  def test_optional_client_methods_return_defaults_when_unimplemented
    result = @agent_conn.conn.send_request(ACP::CLIENT_METHODS["terminal_create"], { "sessionId" => "s", "command" => "ls" })
    assert_nil result
    result = @agent_conn.conn.send_request(ACP::CLIENT_METHODS["terminal_kill"], { "sessionId" => "s", "terminalId" => "t" })
    assert_equal({}, result)
  end

  def test_unimplemented_required_agent_method_is_method_not_found
    error = assert_raises(ACP::RequestError) { @client.load_session(cwd: "/tmp", session_id: "x") }
    assert_equal(-32601, error.code)
  end

  def test_invalid_params_are_rejected_before_reaching_handler
    error = assert_raises(ACP::RequestError) do
      @client.conn.send_request(ACP::AGENT_METHODS["session_prompt"], { "sessionId" => "s" })
    end
    assert_equal(-32602, error.code)
    assert_empty @agent.requests
  end

  def test_cancel_notification_and_set_config_option
    @client.cancel(session_id: "sess_1")
    @client.set_session_config_option(session_id: "sess_1", config_id: "verbose", value: true)
    @client.set_session_config_option(session_id: "sess_1", config_id: "model", value: "fast")

    assert_equal ["sess_1"], @agent.cancelled
    boolean, select = @agent.requests.last(2)
    assert_instance_of S::SetSessionConfigOptionBooleanRequest, boolean
    assert_equal true, boolean.value
    assert_instance_of S::SetSessionConfigOptionSelectRequest, select
    assert_equal "fast", select.value
  end

  def test_extension_methods
    result = @client.ext_method("custom/ping", { "x" => 1 })
    assert_equal({ "echo" => { "x" => 1 } }, result)
    assert_equal [["custom/ping", { "x" => 1 }]], @agent.ext_calls

    error = assert_raises(ACP::RequestError) { @agent_conn.ext_method("nope") }
    assert_equal(-32601, error.code)
  end

  def test_meta_is_forwarded
    @client.new_session(cwd: "/tmp", meta: { "traceId" => "t-1" })
    assert_equal({ "traceId" => "t-1" }, @agent.requests.last.field_meta)
  end
end
