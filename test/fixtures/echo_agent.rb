# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __dir__)
require "acp_sdk_async"

class EchoAgent
  S = ACP::Schema

  def on_connect(connection)
    @connection = connection
  end

  def initialize_acp(request)
    warn "echo-agent: initialize from #{request.client_info&.name || 'unknown'}"
    S::InitializeResponse.new(
      protocol_version: request.protocol_version,
      agent_info: S::Implementation.new(name: "echo-agent", version: "0.0.1")
    )
  end

  def new_session(request)
    warn "echo-agent: new session in #{request.cwd}"
    S::NewSessionResponse.new(session_id: "echo-#{Process.pid}")
  end

  def prompt(request)
    text = request.prompt.map { |block| block.respond_to?(:text) ? block.text : "" }.join
    warn "echo-agent: prompt #{text.inspect}"
    @connection.session_update(
      session_id: request.session_id,
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: text.reverse))
    )
    S::PromptResponse.new(stop_reason: "end_turn")
  end

  def cancel(_notification); end

  def ext_method(name, params)
    sleep(params.fetch("seconds", 5)) if name == "sleep"
    { "name" => name, "cwd" => Dir.pwd, "params" => params }
  end
end

ACP::Agent.run_agent(EchoAgent.new)
