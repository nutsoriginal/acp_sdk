# frozen_string_literal: true

require_relative "test_helper"

class AcpSchemaTest < Minitest::Test
  S = ACP::Schema

  GOLDEN_DIR = File.expand_path("golden", __dir__)

  GOLDEN_CASES = {
    "cancel_notification" => S::CancelNotification,
    "content_audio" => S::AudioContentBlock,
    "content_image" => S::ImageContentBlock,
    "content_resource_blob" => S::EmbeddedResourceContentBlock,
    "content_resource_link" => S::ResourceContentBlock,
    "content_resource_text" => S::EmbeddedResourceContentBlock,
    "content_text" => S::TextContentBlock,
    "fs_read_text_file_request" => S::ReadTextFileRequest,
    "fs_read_text_file_response" => S::ReadTextFileResponse,
    "fs_write_text_file_request" => S::WriteTextFileRequest,
    "initialize_request" => S::InitializeRequest,
    "initialize_response" => S::InitializeResponse,
    "new_session_request" => S::NewSessionRequest,
    "new_session_response" => S::NewSessionResponse,
    "permission_outcome_cancelled" => S::DeniedOutcome,
    "permission_outcome_selected" => S::AllowedOutcome,
    "prompt_request" => S::PromptRequest,
    "request_permission_request" => S::RequestPermissionRequest,
    "request_permission_response_selected" => S::RequestPermissionResponse,
    "session_update_agent_message_chunk" => S::AgentMessageChunk,
    "session_update_agent_thought_chunk" => S::AgentThoughtChunk,
    "session_update_compaction_summary_chunk" => S::SessionUpdateCompactionSummaryChunk,
    "session_update_compaction_update" => S::SessionUpdateCompactionUpdate,
    "session_update_config_option_update" => S::ConfigOptionUpdate,
    "session_update_plan" => S::AgentPlanUpdate,
    "session_update_tool_call" => S::ToolCallStart,
    "session_update_tool_call_edit" => S::ToolCallStart,
    "session_update_tool_call_locations_rawinput" => S::ToolCallStart,
    "session_update_tool_call_read" => S::ToolCallStart,
    "session_update_tool_call_update_content" => S::ToolCallProgress,
    "session_update_tool_call_update_more_fields" => S::ToolCallProgress,
    "session_update_user_message_chunk" => S::UserMessageChunk,
    "set_session_config_option_request" => S::SetSessionConfigOptionSelectRequest,
    "set_session_config_option_response" => S::SetSessionConfigOptionResponse,
    "tool_content_content_text" => S::ContentToolCallContent,
    "tool_content_diff" => S::FileEditToolCallContent,
    "tool_content_diff_no_old" => S::FileEditToolCallContent,
    "tool_content_terminal" => S::TerminalToolCallContent
  }.freeze

  GOLDEN_CASES.each do |name, klass|
    define_method(:"test_golden_roundtrip_#{name}") do
      raw = JSON.parse(File.read(File.join(GOLDEN_DIR, "#{name}.json")))
      model = klass.coerce(raw)
      assert_instance_of klass, model
      assert_equal raw, model.to_h
      assert_equal model, klass.coerce(model.to_h)
    end
  end

  def test_all_golden_fixtures_are_covered
    fixtures = Dir[File.join(GOLDEN_DIR, "*.json")].map { |path| File.basename(path, ".json") }.sort
    assert_equal fixtures, GOLDEN_CASES.keys.sort
  end

  def test_session_update_union_dispatches_by_tag
    %w[session_update_tool_call session_update_agent_message_chunk session_update_plan].each do |name|
      raw = JSON.parse(File.read(File.join(GOLDEN_DIR, "#{name}.json")))
      assert_instance_of GOLDEN_CASES[name], S::SessionUpdate.coerce(raw)
    end
  end

  def test_base_roundtrip_with_meta
    request = S::InitializeRequest.new(
      protocol_version: 1,
      client_info: S::Implementation.new(name: "test", version: "0.1"),
      field_meta: { "traceId" => "abc" }
    )
    hash = request.to_h
    assert_equal 1, hash["protocolVersion"]
    assert_equal "test", hash["clientInfo"]["name"]
    assert_equal "abc", hash["_meta"]["traceId"]

    restored = S::InitializeRequest.from_hash(hash)
    assert_equal 1, restored.protocol_version
    assert_equal "abc", restored.field_meta["traceId"]
    assert_equal "test", restored.client_info.name
  end

  def test_false_values_are_preserved
    caps = S::ClientCapabilities.from_hash({ "fs" => { "readTextFile" => false, "writeTextFile" => true } })
    assert_equal false, caps.fs.read_text_file
    assert_equal true, caps.fs.write_text_file
    assert_equal({ "fs" => { "readTextFile" => false, "writeTextFile" => true } }, caps.to_h)
  end

  def test_defaults_are_available_but_not_serialized
    caps = S::ClientCapabilities.from_hash({})
    assert_equal false, caps.terminal
    assert_equal false, caps.fs.read_text_file
    assert_equal({}, caps.to_h)

    caps.terminal = true
    assert_equal({ "terminal" => true }, caps.to_h)
  end

  def test_missing_required_field_raises
    error = assert_raises(S::ValidationError) { S::PromptRequest.coerce({ "prompt" => [] }) }
    assert_match(/sessionId/, error.message)
  end

  def test_wrong_scalar_type_raises_with_path
    error = assert_raises(S::ValidationError) { S::PromptRequest.coerce({ "sessionId" => 1, "prompt" => [] }) }
    assert_equal ["sessionId"], error.path
  end

  def test_default_on_error_and_skip_invalid_items
    tool_call = S::ToolCall.coerce(
      "toolCallId" => "c1",
      "title" => "t",
      "kind" => "bogus",
      "status" => 42,
      "content" => [
        { "type" => "content", "content" => { "type" => "text", "text" => "a" } },
        { "type" => "unknown" }
      ]
    )
    assert_nil tool_call.kind
    assert_nil tool_call.status
    assert_equal 1, tool_call.content.size
    assert_equal "a", tool_call.content.first.content.text
  end

  def test_enum_validation
    assert_equal "end_turn", S::PromptResponse.coerce({ "stopReason" => "end_turn" }).stop_reason
    assert_raises(S::ValidationError) { S::PromptResponse.coerce({ "stopReason" => "nope" }) }
    assert_raises(S::ValidationError) { S::PromptResponse.new(stop_reason: "nope") }
  end

  def test_open_enum_accepts_unknown_values
    assert_equal "custom", S::CompactionStatus.coerce("custom")
  end

  def test_union_catch_all_variants
    assert_instance_of S::OtherElicitationResponse, S::CreateElicitationResponse.coerce({ "action" => "weird" })
    assert_instance_of S::DeclineElicitationResponse, S::CreateElicitationResponse.coerce({ "action" => "decline" })
  end

  def test_union_accepts_model_instances_of_its_variants
    response = S::RequestPermissionResponse.new(outcome: S::AllowedOutcome.new(option_id: "allow"))
    assert_equal({ "outcome" => { "outcome" => "selected", "optionId" => "allow" } }, response.to_h)

    update = S::SessionNotification.new(session_id: "s", update: S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "hi")))
    assert_equal "agent_message_chunk", update.to_h.dig("update", "sessionUpdate")
  end

  def test_union_rejects_model_instances_that_are_not_variants
    error = assert_raises(S::ValidationError) do
      S::RequestPermissionResponse.new(outcome: S::SelectedPermissionOutcome.new(option_id: "allow"))
    end
    assert_match(/no variant matches outcome=nil/, error.message)

    assert_raises(S::ValidationError) do
      S::SessionNotification.new(session_id: "s", update: S::ContentChunk.new(content: S::TextContentBlock.new(text: "hi")))
    end
  end

  def test_known_tag_with_invalid_body_does_not_fall_back_to_catch_all
    error = assert_raises(S::ValidationError) { S::SessionUpdate.coerce({ "sessionUpdate" => "tool_call" }) }
    assert_match(/toolCallId/, error.message)
    assert_raises(S::ValidationError) { S::McpServer.coerce({ "type" => "http", "name" => "x" }) }
  end

  def test_untagged_union_variants
    stdio = S::McpServer.coerce({ "name" => "x", "command" => "c", "args" => [], "env" => [] })
    assert_instance_of S::McpServerStdio, stdio
    http = S::McpServer.coerce({ "type" => "http", "name" => "x", "url" => "http://a", "headers" => [] })
    assert_instance_of S::HttpMcpServer, http
  end

  def test_constructor_coerces_nested_hashes
    block = S::ContentToolCallContent.new(content: { "type" => "text", "text" => "x" })
    assert_instance_of S::TextContentBlock, block.content
    assert_equal({ "type" => "content", "content" => { "type" => "text", "text" => "x" } }, block.to_h)
  end

  def test_constructor_rejects_unknown_fields
    assert_raises(ArgumentError) { S::PromptResponse.new(bogus: 1) }
  end

  def test_protocol_version_is_coerced
    assert_equal 1, S::InitializeResponse.from_hash({ "protocolVersion" => "1" }).protocol_version
    assert_equal 1, S::InitializeRequest.from_hash({ "protocolVersion" => "garbage" }).protocol_version
  end

  def test_snake_case_keys_are_accepted_on_input
    request = S::PromptRequest.coerce({ session_id: "s", prompt: [{ type: "text", text: "hi" }] })
    assert_equal "s", request.session_id
    assert_equal "hi", request.prompt.first.text
  end

  def test_set_session_config_option_request_union
    boolean = S::SetSessionConfigOptionRequest.coerce(
      "sessionId" => "s", "configId" => "c", "type" => "boolean", "value" => true
    )
    assert_instance_of S::SetSessionConfigOptionBooleanRequest, boolean
    select = S::SetSessionConfigOptionRequest.coerce("sessionId" => "s", "configId" => "c", "value" => "fast")
    assert_instance_of S::SetSessionConfigOptionSelectRequest, select
  end

  def test_new_session_request_omits_unset_fields
    hash = S::NewSessionRequest.new(cwd: "/tmp", mcp_servers: []).to_h
    assert_equal({ "cwd" => "/tmp", "mcpServers" => [] }, hash)
  end

  def test_to_camel_and_to_snake
    assert_equal "sessionId", S.to_camel("session_id")
    assert_equal "session_id", S.to_snake("sessionId")
  end

  def test_meta_constants_match_schema
    assert_equal "session/set_mode", ACP::AGENT_METHODS["session_set_mode"]
    assert_equal "session/request_permission", ACP::CLIENT_METHODS["session_request_permission"]
    assert_equal "$/cancel_request", ACP::PROTOCOL_METHODS["cancel_request"]
    assert_equal 1, ACP::PROTOCOL_VERSION
    assert_match(/schema-v1\./, S::SCHEMA_REF)
  end

  def test_generated_schema_is_up_to_date
    require_relative "../scripts/gen_schema"
    generator = ACP::SchemaGenerator::Generator.new
    assert_equal File.read(ACP::SchemaGenerator::OUT_SCHEMA), generator.render_schema
    assert_equal File.read(ACP::SchemaGenerator::OUT_META), generator.render_meta
  end
end
