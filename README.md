# acp_sdk

Ruby SDK for the [Agent Client Protocol](https://agentclientprotocol.com) (ACP): typed schema models generated from the official `schema.json`, a JSON-RPC 2.0 connection over NDJSON, client- and agent-side wrappers, and helpers for spawning agents over stdio.

Requires Ruby 3.2+ and runs on [`async`](https://github.com/socketry/async), the same cooperative scheduler used by Falcon. The public API is blocking (`client.prompt(...)`) like a normal Ruby method; inside a reactor those calls yield to other tasks instead of occupying a thread.

## Installation

```ruby
gem "acp_sdk", git: "git@github.com:nutsoriginal/acp_sdk.git", branch: "main"
```

```bash
bundle install
```

## Client: talk to an agent over stdio

ACP calls must run inside an Async reactor. `Sync { ... }` starts one, or reuses the current task if you are already inside Falcon/`Async`.

```ruby
require "acp_sdk"

S = ACP::Schema

class MyClient
  def session_update(notification)
    update = notification.update
    print update.content.text if update.is_a?(S::AgentMessageChunk)
  end

  def request_permission(request)
    option = request.options.find { |candidate| candidate.kind.start_with?("allow") }
    return S::RequestPermissionResponse.new(outcome: S::DeniedOutcome.new) if option.nil?

    S::RequestPermissionResponse.new(outcome: S::AllowedOutcome.new(option_id: option.option_id))
  end
end

Sync do
  process = ACP::Stdio.spawn_agent("my-agent", "--acp", cwd: Dir.pwd, stderr: :log)
  client = process.connect(MyClient.new)

  client.initialize_agent(client_info: S::Implementation.new(name: "my-client", version: "1.0"))
  session = client.new_session(cwd: Dir.pwd)
  response = client.prompt(
    session_id: session.session_id,
    prompt: [S::TextContentBlock.new(text: "Hello!")]
  )
  puts response.stop_reason

  client.close
  process.close
end
```

`ACP::Client::Connection` exposes every agent method (`initialize_agent`, `authenticate`, `new_session`, `load_session`, `list_sessions`, `fork_session`, `resume_session`, `set_session_mode`, `set_session_config_option`, `prompt`, `cancel`, `logout`, `ext_method`, `ext_notification`, ...). Request arguments are keyword arguments matching the schema fields in snake_case; responses come back as typed models.

The client handler receives typed models too: `session_update(S::SessionNotification)`, `request_permission(S::RequestPermissionRequest)`, `read_text_file`, `write_text_file`, `create_terminal`, `terminal_output`, `release_terminal`, `wait_for_terminal_exit`, `kill_terminal`, `create_elicitation`, `complete_elicitation`, `ext_method(name, params)`, `ext_notification(name, params)`. Methods the handler does not implement return `method not found` to the peer.

Incoming requests run as child tasks so a handler can call back into the peer without deadlocking. Notifications are delivered in order on a single task. After `prompt` returns, queued `session/update` handlers have already finished.

## Agent: serve the protocol over stdin/stdout

```ruby
require "acp_sdk"

S = ACP::Schema

class EchoAgent
  def on_connect(connection)
    @connection = connection
  end

  def initialize_acp(request)
    S::InitializeResponse.new(
      protocol_version: request.protocol_version,
      agent_info: S::Implementation.new(name: "echo-agent", version: "0.1")
    )
  end

  def new_session(_request)
    S::NewSessionResponse.new(session_id: SecureRandom.uuid)
  end

  def prompt(request)
    text = request.prompt.map { |block| block.respond_to?(:text) ? block.text : "" }.join
    @connection.session_update(
      session_id: request.session_id,
      update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: text.reverse))
    )
    S::PromptResponse.new(stop_reason: "end_turn")
  end

  def cancel(_notification); end
end

ACP::Agent.run_agent(EchoAgent.new)
```

`run_agent` starts the reactor with `Sync` and listens until stdin closes. The ACP `initialize` method maps to `initialize_acp` on the agent handler so it does not collide with Ruby's constructor. Every other method keeps its snake_case name (`new_session`, `load_session`, `prompt`, `cancel`, `set_session_mode`, ...).

## Schema models

`ACP::Schema` contains a class for every definition in the ACP schema. Models accept snake_case keyword arguments, serialize to camelCase JSON with `to_h`/`to_json`, and parse with `from_hash`. Unions (`ContentBlock`, `SessionUpdate`, `ToolCallContent`, ...) resolve to the right variant automatically; enums and required fields are validated on construction and on parse.

```ruby
block = ACP::Schema::ContentBlock.from_hash({ "type" => "text", "text" => "hi" })
block.class        # => ACP::Schema::TextContentBlock
block.to_h         # => { "type" => "text", "text" => "hi" }
```

`ACP::PROTOCOL_VERSION`, `ACP::AGENT_METHODS`, `ACP::CLIENT_METHODS` and `ACP::PROTOCOL_METHODS` mirror the official `meta.json`.

## Lower level

`ACP::Connection` is the transport-agnostic JSON-RPC layer (requests with optional timeouts, ordered notification delivery, observers for tracing traffic). `ACP::NdjsonTransport` wraps a pair of IO objects; `ACP::MemoryTransport.pair` gives two in-memory ends for tests.

Logging goes through `ACP.logger` (a `Logger`, `WARN` level by default); assign your own to integrate with the host application.

## Updating the schema

`schema/schema.json`, `schema/meta.json` and `schema/VERSION` are vendored from the [ACP repository](https://github.com/agentclientprotocol/agent-client-protocol). After replacing them run:

```bash
bundle exec rake gen_schema
bundle exec rake test
```

`lib/acp/schema.rb` and `lib/acp/meta.rb` are generated files; do not edit them by hand.

## Development

```bash
bundle install
bundle exec rake test
```

## License

This project is dedicated to the public domain under the [Unlicense](https://unlicense.org). You may use, copy, modify, and distribute the code without restriction.
