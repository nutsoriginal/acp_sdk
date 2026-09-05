# frozen_string_literal: true

require_relative "test_helper"

# End-to-end coverage for every Client->Agent and Agent->Client method.
# A FullAgent implements the whole agent surface, a FullClient the whole
# client surface; the pair talks over an in-memory transport.
class AcpMethodsTest < Minitest::Test
  S = ACP::Schema

  PERMISSION_OPTIONS = [
    S::PermissionOption.new(option_id: "allow", name: "Allow", kind: "allow_once")
  ].freeze

  class FullAgent
    attr_reader :cancelled, :ext_calls, :ext_notifications

    def initialize
      @cancelled = []
      @ext_calls = []
      @ext_notifications = []
    end

    def initialize_acp(request)
      S::InitializeResponse.new(
        protocol_version: request.protocol_version,
        agent_info: S::Implementation.new(name: "full-agent", version: "9.9")
      )
    end

    def authenticate(_request)
      S::AuthenticateResponse.new
    end

    def new_session(request)
      S::NewSessionResponse.new(session_id: "sess-new-#{request.cwd}")
    end

    def load_session(_request)
      S::LoadSessionResponse.new
    end

    def list_sessions(_request)
      S::ListSessionsResponse.new(sessions: [
                                    S::SessionInfo.new(session_id: "s1", cwd: "/tmp")
                                  ])
    end

    def fork_session(request)
      S::ForkSessionResponse.new(session_id: "fork-#{request.session_id}")
    end

    def resume_session(_request)
      S::ResumeSessionResponse.new
    end

    def close_session(_request)
      S::CloseSessionResponse.new
    end

    def delete_session(_request)
      S::DeleteSessionResponse.new
    end

    def set_session_mode(_request)
      S::SetSessionModeResponse.new
    end

    def set_session_config_option(_request)
      S::SetSessionConfigOptionResponse.new(config_options: [])
    end

    def prompt(_request)
      S::PromptResponse.new(stop_reason: "end_turn")
    end

    def cancel(notification)
      @cancelled << notification.session_id
    end

    def logout(_request)
      S::LogoutResponse.new
    end

    def list_providers(_request)
      S::ListProvidersResponse.new(providers: [])
    end

    def set_provider(_request)
      S::SetProviderResponse.new
    end

    def disable_provider(_request)
      S::DisableProviderResponse.new
    end

    def mcp_message(_request)
      { "echo" => true }
    end

    def ext_method(name, params)
      @ext_calls << [name, params]
      { "name" => name }
    end

    def ext_notification(name, params)
      @ext_notifications << [name, params]
    end
  end

  # Handlers returning nil exercise the normalize: true routes
  # (nil result becomes {} on the wire).
  class NilAgent
    def initialize_acp(request)
      S::InitializeResponse.new(
        protocol_version: request.protocol_version,
        agent_info: S::Implementation.new(name: "nil-agent", version: "1")
      )
    end

    def authenticate(_request) = nil
    def new_session(_request) = S::NewSessionResponse.new(session_id: "s")
    def load_session(_request) = nil
    def list_sessions(_request) = S::ListSessionsResponse.new(sessions: [])
    def fork_session(request) = S::ForkSessionResponse.new(session_id: "f-#{request.session_id}")
    def resume_session(_request) = S::ResumeSessionResponse.new
    def close_session(_request) = nil
    def delete_session(_request) = nil
    def set_session_mode(_request) = nil

    # NOTE: SetSessionConfigOptionResponse requires configOptions, so a nil
    # return cannot round-trip (normalize turns it into {}, which is invalid).
    # A real agent must return a proper response here.
    def set_session_config_option(_request)
      S::SetSessionConfigOptionResponse.new(config_options: [])
    end

    def prompt(_request) = S::PromptResponse.new(stop_reason: "end_turn")
    def cancel(_notification) = nil
    def logout(_request) = nil
    def list_providers(_request) = S::ListProvidersResponse.new(providers: [])
    def set_provider(_request) = nil
    def disable_provider(_request) = nil
    def mcp_message(_request) = {}
  end

  class FullClient
    attr_reader :updates, :completions, :ext_calls, :ext_notifications

    def initialize
      @updates = []
      @completions = []
      @ext_calls = []
      @ext_notifications = []
    end

    def write_text_file(_request)
      S::WriteTextFileResponse.new
    end

    def read_text_file(request)
      S::ReadTextFileResponse.new(content: "content:#{request.path}")
    end

    def request_permission(request)
      S::RequestPermissionResponse.new(
        outcome: S::AllowedOutcome.new(option_id: request.options.first.option_id)
      )
    end

    def create_terminal(_request)
      S::CreateTerminalResponse.new(terminal_id: "term-1")
    end

    def terminal_output(_request)
      S::TerminalOutputResponse.new(output: "out", truncated: false)
    end

    def release_terminal(_request)
      S::ReleaseTerminalResponse.new
    end

    def wait_for_terminal_exit(_request)
      S::WaitForTerminalExitResponse.new(exit_code: 0)
    end

    def kill_terminal(_request)
      S::KillTerminalResponse.new
    end

    def create_elicitation(_request)
      S::DeclineElicitationResponse.new
    end

    def mcp_connect(_request)
      S::ConnectMcpResponse.new(connection_id: "mcp-1")
    end

    def mcp_message(_request)
      { "ok" => true }
    end

    def mcp_disconnect(_request)
      S::DisconnectMcpResponse.new
    end

    def session_update(notification)
      @updates << notification
    end

    def complete_elicitation(notification)
      @completions << notification
    end

    def ext_method(name, params)
      @ext_calls << [name, params]
      { "client" => name }
    end

    def ext_notification(name, params)
      @ext_notifications << [name, params]
    end
  end

  def setup
    @previous_logger = ACP.logger
    ACP.logger = Logger.new(File::NULL)
    @connections = []
  end

  def teardown
    @connections.each(&:close)
    ACP.logger = @previous_logger
  end

  def wire(agent: FullAgent.new, client: FullClient.new)
    ct, at = ACP.memory_transport_pair
    agent_conn = ACP::Agent::Connection.new(agent, at)
    client_conn = ACP::Client::Connection.new(client, ct)
    @connections.push(agent_conn.conn, client_conn.conn)
    agent_conn.start
    client_conn.start
    [agent, client, agent_conn, client_conn]
  end

  # --- Client -> Agent: every method ---

  def test_client_to_agent_initialize_and_authenticate
    _a, _c, _ac, cc = wire
    init = cc.initialize_agent(client_info: S::Implementation.new(name: "t", version: "1"))
    assert_equal "full-agent", init.agent_info.name
    assert_equal 1, init.protocol_version
    assert_instance_of S::AuthenticateResponse, cc.authenticate(method_id: "m")
  end

  def test_client_to_agent_sessions
    _a, _c, _ac, cc = wire
    session = cc.new_session(cwd: "/work")
    assert_equal "sess-new-/work", session.session_id

    assert_instance_of S::LoadSessionResponse, cc.load_session(cwd: "/work", session_id: "s1")

    list = cc.list_sessions(cwd: "/work")
    assert_equal ["s1"], list.sessions.map(&:session_id)

    forked = cc.fork_session(session_id: "s1", cwd: "/work")
    assert_equal "fork-s1", forked.session_id

    assert_instance_of S::ResumeSessionResponse, cc.resume_session(session_id: "s1", cwd: "/work")
    assert_instance_of S::CloseSessionResponse, cc.close_session(session_id: "s1")
    assert_instance_of S::DeleteSessionResponse, cc.delete_session(session_id: "s1")
  end

  def test_client_to_agent_mode_config_prompt_cancel_logout
    agent, _c, _ac, cc = wire
    assert_instance_of S::SetSessionModeResponse, cc.set_session_mode(session_id: "s", mode_id: "m")
    assert_instance_of S::SetSessionConfigOptionResponse,
                       cc.set_session_config_option(session_id: "s", config_id: "c", value: true)
    assert_instance_of S::SetSessionConfigOptionResponse,
                       cc.set_config_option(session_id: "s", config_id: "c", value: "fast")

    response = cc.prompt(session_id: "s", prompt: [S::TextContentBlock.new(text: "hi")])
    assert_equal "end_turn", response.stop_reason

    cc.cancel(session_id: "s")
    sleep 0.2
    assert_equal ["s"], agent.cancelled
    assert_instance_of S::LogoutResponse, cc.logout
  end

  def test_client_to_agent_providers_and_mcp
    _a, _c, _ac, cc = wire
    providers = cc.conn.send_request(
      ACP::AGENT_METHODS["providers_list"], S::ListProvidersRequest.new
    )
    assert_equal({ "providers" => [] }, providers)

    set_result = cc.conn.send_request(
      ACP::AGENT_METHODS["providers_set"],
      S::SetProviderRequest.new(provider_id: "p", api_type: "openai", base_url: "http://x")
    )
    assert_equal({}, set_result)

    disable_result = cc.conn.send_request(
      ACP::AGENT_METHODS["providers_disable"],
      S::DisableProviderRequest.new(provider_id: "p")
    )
    assert_equal({}, disable_result)

    mcp_result = cc.conn.send_request(
      ACP::AGENT_METHODS["mcp_message"],
      S::MessageMcpRequest.new(connection_id: "c", method_name: "ping")
    )
    assert_equal({ "echo" => true }, mcp_result)
  end

  def test_client_to_agent_ext_roundtrip
    agent, _c, _ac, cc = wire
    assert_equal({ "name" => "ping" }, cc.ext_method("ping", { "x" => 1 }))
    assert_equal [["ping", { "x" => 1 }]], agent.ext_calls

    cc.ext_notification("n", { "y" => 2 })
    sleep 0.2
    assert_equal [["n", { "y" => 2 }]], agent.ext_notifications
  end

  def test_agent_normalize_nil_becomes_empty_hash
    _a, _c, _ac, cc = wire(agent: NilAgent.new)
    assert_instance_of S::AuthenticateResponse, cc.authenticate(method_id: "m")
    assert_instance_of S::LoadSessionResponse, cc.load_session(cwd: "/w", session_id: "s")
    assert_instance_of S::CloseSessionResponse, cc.close_session(session_id: "s")
    assert_instance_of S::DeleteSessionResponse, cc.delete_session(session_id: "s")
    assert_instance_of S::SetSessionModeResponse, cc.set_session_mode(session_id: "s", mode_id: "m")
    assert_instance_of S::SetSessionConfigOptionResponse,
                       cc.set_session_config_option(session_id: "s", config_id: "c", value: true)
    assert_instance_of S::LogoutResponse, cc.logout
  end

  def test_unimplemented_required_agent_method_is_method_not_found
    _a, _c, _ac, cc = wire(agent: Object.new)
    error = assert_raises(ACP::RequestError) { cc.new_session(cwd: "/tmp") }
    assert_equal(-32601, error.code)
    error = assert_raises(ACP::RequestError) { cc.prompt(session_id: "s", prompt: []) }
    assert_equal(-32601, error.code)
  end

  def test_agent_legacy_set_config_option_name_is_accepted
    legacy = Object.new
    def legacy.set_config_option(_request) = ACP::Schema::SetSessionConfigOptionResponse.new(config_options: [])
    _a, _c, _ac, cc = wire(agent: legacy)
    # Router falls back to the second name; initialize is unimplemented so use raw call.
    result = cc.conn.send_request(
      ACP::AGENT_METHODS["session_set_config_option"],
      S::SetSessionConfigOptionSelectRequest.new(session_id: "s", config_id: "c", value: "v")
    )
    assert_equal({ "configOptions" => [] }, result)
  end

  # --- Agent -> Client: every method ---

  def test_agent_to_client_session_update_and_permission
    _a, client, ac, cc = wire
    ac.session_update(
      session_id: "s",
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "hi"))
    )
    # Barrier request first: drain only covers the worker queue, so make sure
    # the notification was received (and queued) before draining.
    ac.read_text_file(session_id: "s", path: "p")
    assert cc.drain_notifications(timeout: 2.0)
    assert_equal 1, client.updates.size
    assert_equal "hi", client.updates.first.update.content.text

    response = ac.request_permission(
      session_id: "s",
      tool_call: S::ToolCallUpdate.new(tool_call_id: "c1"),
      options: PERMISSION_OPTIONS
    )
    assert_instance_of S::RequestPermissionResponse, response
    assert_equal "allow", response.outcome.option_id
  end

  def test_agent_to_client_fs
    _a, _c, ac, _cc = wire
    read = ac.read_text_file(session_id: "s", path: "/etc/hosts")
    assert_equal "content:/etc/hosts", read.content
    assert_instance_of S::WriteTextFileResponse, ac.write_text_file(session_id: "s", path: "p", content: "c")
  end

  def test_agent_to_client_terminals
    _a, _c, ac, _cc = wire
    created = ac.create_terminal(session_id: "s", command: "ls")
    assert_equal "term-1", created.terminal_id

    output = ac.terminal_output(session_id: "s", terminal_id: "term-1")
    assert_equal "out", output.output
    assert_equal false, output.truncated

    assert_instance_of S::ReleaseTerminalResponse, ac.release_terminal(session_id: "s", terminal_id: "t")
    exited = ac.wait_for_terminal_exit(session_id: "s", terminal_id: "t")
    assert_equal 0, exited.exit_code
    assert_instance_of S::KillTerminalResponse, ac.kill_terminal(session_id: "s", terminal_id: "t")
  end

  def test_agent_to_client_elicitation_and_complete
    _a, client, ac, cc = wire
    mode = S::ElicitationFormSessionMode.new(
      requested_schema: S::ElicitationSchema.new(properties: {}, required: []),
      session_id: "s",
      tool_call_id: "c"
    )
    response = ac.create_elicitation(message: "Fill?", mode: mode)
    assert_instance_of S::DeclineElicitationResponse, response

    ac.complete_elicitation(elicitation_id: "e1")
    ac.read_text_file(session_id: "s", path: "p")
    assert cc.drain_notifications(timeout: 2.0)
    assert_equal ["e1"], client.completions.map(&:elicitation_id)
  end

  def test_agent_to_client_mcp
    _a, _c, ac, _cc = wire
    connected = ac.conn.send_request(
      ACP::CLIENT_METHODS["mcp_connect"], S::ConnectMcpRequest.new(server_id: "srv")
    )
    assert_equal({ "connectionId" => "mcp-1" }, connected)

    message = ac.conn.send_request(
      ACP::CLIENT_METHODS["mcp_message"], S::MessageMcpRequest.new(connection_id: "m", method_name: "ping")
    )
    assert_equal({ "ok" => true }, message)

    dis = ac.conn.send_request(
      ACP::CLIENT_METHODS["mcp_disconnect"], S::DisconnectMcpRequest.new(connection_id: "m")
    )
    assert_equal({}, dis)
  end

  def test_agent_to_client_ext_roundtrip
    _a, client, ac, _cc = wire
    assert_equal({ "client" => "ping" }, ac.ext_method("ping", { "x" => 1 }))
    assert_equal [["ping", { "x" => 1 }]], client.ext_calls

    ac.ext_notification("n", { "y" => 2 })
    sleep 0.2
    assert_equal [["n", { "y" => 2 }]], client.ext_notifications
  end

  def test_unimplemented_optional_client_methods_return_defaults
    _a, _c, ac, _cc = wire(client: Object.new)
    assert_nil ac.conn.send_request(
      ACP::CLIENT_METHODS["terminal_create"],
      S::CreateTerminalRequest.new(session_id: "s", command: "ls")
    )
    assert_nil ac.conn.send_request(
      ACP::CLIENT_METHODS["terminal_output"],
      S::TerminalOutputRequest.new(session_id: "s", terminal_id: "t")
    )
    assert_nil ac.conn.send_request(
      ACP::CLIENT_METHODS["terminal_wait_for_exit"],
      S::WaitForTerminalExitRequest.new(session_id: "s", terminal_id: "t")
    )
    assert_equal({},
                 ac.conn.send_request(
                   ACP::CLIENT_METHODS["terminal_release"],
                   S::ReleaseTerminalRequest.new(session_id: "s", terminal_id: "t")
                 ))
    assert_equal({},
                 ac.conn.send_request(
                   ACP::CLIENT_METHODS["terminal_kill"],
                   S::KillTerminalRequest.new(session_id: "s", terminal_id: "t")
                 ))
  end

  def test_unimplemented_required_client_method_is_method_not_found
    _a, _c, ac, _cc = wire(client: Object.new)
    error = assert_raises(ACP::RequestError) do
      ac.conn.send_request(
        ACP::CLIENT_METHODS["fs_read_text_file"],
        S::ReadTextFileRequest.new(session_id: "s", path: "p")
      )
    end
    assert_equal(-32601, error.code)
  end

  def test_missing_client_notification_handler_is_silent
    _a, _c, ac, _cc = wire(client: Object.new)
    # Must not raise: notifications have no response channel.
    ac.session_update(
      session_id: "s",
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "hi"))
    )
    ac.complete_elicitation(elicitation_id: "e1")
  end

  # --- Observers / lifecycle ---

  def test_remove_observer_stops_events
    _a, _c, ac, cc = wire
    events = []
    observer = proc { |e| events << e.direction }
    cc.add_observer(observer)
    cc.conn.remove_observer(observer)
    cc.initialize_agent
    assert_empty events
    assert_same observer, ac.add_observer(observer)
  end

  def test_on_connect_hooks_fire
    agent_connected = nil
    client_connected = nil
    agent = Object.new
    agent.define_singleton_method(:on_connect) { |c| agent_connected = c }
    agent.define_singleton_method(:initialize_acp) do |req|
      S::InitializeResponse.new(
        protocol_version: req.protocol_version,
        agent_info: S::Implementation.new(name: "a", version: "1")
      )
    end
    client_handler = Object.new
    client_handler.define_singleton_method(:on_connect) { |c| client_connected = c }
    _a, _c, ac, cc = wire(agent: agent, client: client_handler)
    assert_same ac, agent_connected
    assert_same cc, client_connected
  end
end
