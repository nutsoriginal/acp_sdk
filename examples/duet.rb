# frozen_string_literal: true

# In-process agent<->client demo over in-memory transports (no subprocess).
#
# Run with:
#   ruby -Ilib examples/duet.rb ["message 1" "message 2" ...]
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "acp_sdk_async"

S = ACP::Schema

# Minimal agent: echoes prompts back with a "Client sent:" preamble.
class DuetAgent
  def on_connect(connection)
    @connection = connection
  end

  def initialize_acp(request)
    S::InitializeResponse.new(
      protocol_version: request.protocol_version,
      agent_info: S::Implementation.new(name: "duet-agent", version: "0.1.0")
    )
  end

  def new_session(_request)
    S::NewSessionResponse.new(session_id: "duet-1")
  end

  def prompt(request)
    text = request.prompt.map { |block| block.respond_to?(:text) ? block.text : "" }.join
    @connection.session_update(
      session_id: request.session_id,
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "Client sent:"))
    )
    @connection.session_update(
      session_id: request.session_id,
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: text))
    )
    S::PromptResponse.new(stop_reason: "end_turn")
  end

  def cancel(_notification); end
end

# Minimal client: prints agent message chunks.
class DuetClient
  def session_update(notification)
    update = notification.update
    return unless update.is_a?(S::AgentMessageChunk) && update.content.is_a?(S::TextContentBlock)

    puts "| Agent: #{update.content.text}"
  end
end

Sync do
  client_transport, agent_transport = ACP.memory_transport_pair
  agent_conn = ACP::Agent::Connection.new(DuetAgent.new, agent_transport)
  client_conn = ACP::Client::Connection.new(DuetClient.new, client_transport)
  agent_conn.start
  client_conn.start

  begin
    client_conn.initialize_agent(
      client_info: S::Implementation.new(name: "duet-client", version: "0.1.0")
    )
    session = client_conn.new_session(cwd: Dir.pwd)

    messages = ARGV.empty? ? ["Hello, agent!"] : ARGV
    messages.each do |text|
      puts "> #{text}"
      client_conn.prompt(
        session_id: session.session_id,
        prompt: [S::TextContentBlock.new(text: text)]
      )
    end
  ensure
    client_conn.close
    agent_conn.close
  end
end
