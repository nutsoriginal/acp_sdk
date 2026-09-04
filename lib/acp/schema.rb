# frozen_string_literal: true

require_relative "schema_base"

module ACP
  module Schema
    SCHEMA_REF = "refs/tags/schema-v1.21.0"

    class WriteTextFileRequest < Base
      field :session_id, "SessionId", required: true
      field :path, :string, required: true
      field :content, :string, required: true
    end

    class ReadTextFileRequest < Base
      field :session_id, "SessionId", required: true
      field :path, :string, required: true
      field :line, :integer, default_on_error: true
      field :limit, :integer, default_on_error: true
    end

    class RequestPermissionRequest < Base
      field :session_id, "SessionId", required: true
      field :tool_call, "ToolCallUpdate", required: true
      field :options, Types::List.new("PermissionOption"), required: true
    end

    class ToolCallUpdate < Base
      field :tool_call_id, "ToolCallId", required: true
      field :kind, "ToolKind", default_on_error: true
      field :status, "ToolCallStatus", default_on_error: true
      field :title, :string, default_on_error: true
      field :name, :string, default_on_error: true
      field :content, Types::List.new("ToolCallContent", skip_invalid: true), default_on_error: true
      field :locations, Types::List.new("ToolCallLocation", skip_invalid: true), default_on_error: true
      field :raw_input, :any, default_on_error: true
      field :raw_output, :any, default_on_error: true
    end

    class Annotations < Base
      field :audience, Types::List.new("Role", skip_invalid: true), default_on_error: true
      field :last_modified, :string, default_on_error: true
      field :priority, :number, default_on_error: true
    end

    class TextContent < Base
      field :annotations, "Annotations", default_on_error: true
      field :text, :string, required: true
    end

    class ImageContent < Base
      field :annotations, "Annotations", default_on_error: true
      field :data, :string, required: true
      field :mime_type, :string, required: true
      field :uri, :string, default_on_error: true
    end

    class AudioContent < Base
      field :annotations, "Annotations", default_on_error: true
      field :data, :string, required: true
      field :mime_type, :string, required: true
    end

    class ResourceLink < Base
      field :annotations, "Annotations", default_on_error: true
      field :description, :string, default_on_error: true
      field :mime_type, :string, default_on_error: true
      field :name, :string, required: true
      field :size, :integer, default_on_error: true
      field :title, :string, default_on_error: true
      field :uri, :string, required: true
    end

    class TextResourceContents < Base
      field :mime_type, :string, default_on_error: true
      field :text, :string, required: true
      field :uri, :string, required: true
    end

    class BlobResourceContents < Base
      field :blob, :string, required: true
      field :mime_type, :string, default_on_error: true
      field :uri, :string, required: true
    end

    class EmbeddedResource < Base
      field :annotations, "Annotations", default_on_error: true
      field :resource, "EmbeddedResourceResource", required: true
    end

    class Content < Base
      field :content, "ContentBlock", required: true
    end

    class Diff < Base
      field :path, :string, required: true
      field :old_text, :string, default_on_error: true
      field :new_text, :string, required: true
    end

    class Terminal < Base
      field :terminal_id, "TerminalId", required: true
    end

    class ToolCallLocation < Base
      field :path, :string, required: true
      field :line, :integer, default_on_error: true
    end

    class PermissionOption < Base
      field :option_id, "PermissionOptionId", required: true
      field :name, :string, required: true
      field :kind, "PermissionOptionKind", required: true
    end

    class CreateTerminalRequest < Base
      field :session_id, "SessionId", required: true
      field :command, :string, required: true
      field :args, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :env, Types::List.new("EnvVariable", skip_invalid: true), default_on_error: true
      field :cwd, :string, default_on_error: true
      field :output_byte_limit, :integer, default_on_error: true
    end

    class EnvVariable < Base
      field :name, :string, required: true
      field :value, :string, required: true
    end

    class TerminalOutputRequest < Base
      field :session_id, "SessionId", required: true
      field :terminal_id, "TerminalId", required: true
    end

    class ReleaseTerminalRequest < Base
      field :session_id, "SessionId", required: true
      field :terminal_id, "TerminalId", required: true
    end

    class WaitForTerminalExitRequest < Base
      field :session_id, "SessionId", required: true
      field :terminal_id, "TerminalId", required: true
    end

    class KillTerminalRequest < Base
      field :session_id, "SessionId", required: true
      field :terminal_id, "TerminalId", required: true
    end

    class ElicitationSessionScope < Base
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class ElicitationRequestScope < Base
      field :request_id, "RequestId", required: true
    end

    class ElicitationSchema < Base
      field :type, "ElicitationSchemaType", default: "object", default_on_error: true
      field :title, :string, default_on_error: true
      field :properties, Types::Map.new("ElicitationPropertySchema"), default: {}
      field :required, Types::List.new(:string)
      field :description, :string, default_on_error: true
    end

    class EnumOption < Base
      field :const, :string, required: true
      field :title, :string, required: true
      field :description, :string, default_on_error: true
    end

    class StringPropertySchema < Base
      field :title, :string, default_on_error: true
      field :description, :string, default_on_error: true
      field :min_length, :integer
      field :max_length, :integer
      field :pattern, :string
      field :format, "StringFormat"
      field :default, :string, default_on_error: true
      field :enum, Types::List.new(:string)
      field :one_of, Types::List.new("EnumOption")
    end

    class NumberPropertySchema < Base
      field :title, :string, default_on_error: true
      field :description, :string, default_on_error: true
      field :minimum, :number
      field :maximum, :number
      field :default, :number, default_on_error: true
    end

    class IntegerPropertySchema < Base
      field :title, :string, default_on_error: true
      field :description, :string, default_on_error: true
      field :minimum, :integer
      field :maximum, :integer
      field :default, :integer, default_on_error: true
    end

    class BooleanPropertySchema < Base
      field :title, :string, default_on_error: true
      field :description, :string, default_on_error: true
      field :default, :boolean, default_on_error: true
    end

    class StringMultiSelectItemsBase < Base
      field :enum, Types::List.new(:string), required: true
    end

    class TitledMultiSelectItems < Base
      field :any_of, Types::List.new("EnumOption"), required: true
    end

    class MultiSelectPropertySchema < Base
      field :title, :string, default_on_error: true
      field :description, :string, default_on_error: true
      field :min_items, :integer
      field :max_items, :integer
      field :items, "MultiSelectItems", required: true
      field :default, Types::List.new(:string, skip_invalid: true), default_on_error: true
    end

    class ConnectMcpRequest < Base
      field :server_id, "McpServerAcpId", required: true
    end

    class MessageMcpRequest < Base
      field :connection_id, "McpConnectionId", required: true
      field :method_name, :string, key: "method", required: true
      field :params, :object
    end

    class DisconnectMcpRequest < Base
      field :connection_id, "McpConnectionId", required: true
    end

    class InitializeResponse < Base
      field :protocol_version, "ProtocolVersion", required: true
      field :agent_capabilities, "AgentCapabilities", default: {"loadSession" => false, "promptCapabilities" => {"image" => false, "audio" => false, "embeddedContext" => false}, "mcpCapabilities" => {"http" => false, "sse" => false, "acp" => false}, "sessionCapabilities" => {}, "auth" => {}}, default_on_error: true
      field :auth_methods, Types::List.new("AuthMethod", skip_invalid: true), default: [], default_on_error: true
      field :agent_info, "Implementation", default_on_error: true
    end

    class AgentCapabilities < Base
      field :load_session, :boolean, default: false, default_on_error: true
      field :prompt_capabilities, "PromptCapabilities", default: {"image" => false, "audio" => false, "embeddedContext" => false}, default_on_error: true
      field :mcp_capabilities, "McpCapabilities", default: {"http" => false, "sse" => false, "acp" => false}, default_on_error: true
      field :session_capabilities, "SessionCapabilities", default: {}, default_on_error: true
      field :auth, "AgentAuthCapabilities", default: {}, default_on_error: true
      field :providers, "ProvidersCapabilities", default_on_error: true
      field :nes, "NesCapabilities", default_on_error: true
      field :position_encoding, "PositionEncodingKind", default_on_error: true
    end

    class PromptCapabilities < Base
      field :image, :boolean, default: false, default_on_error: true
      field :audio, :boolean, default: false, default_on_error: true
      field :embedded_context, :boolean, default: false, default_on_error: true
    end

    class McpCapabilities < Base
      field :http, :boolean, default: false, default_on_error: true
      field :sse, :boolean, default: false, default_on_error: true
      field :acp, :boolean, default: false, default_on_error: true
    end

    class SessionCapabilities < Base
      field :list, "SessionListCapabilities", default_on_error: true
      field :delete, "SessionDeleteCapabilities", default_on_error: true
      field :additional_directories, "SessionAdditionalDirectoriesCapabilities", default_on_error: true
      field :fork, "SessionForkCapabilities", default_on_error: true
      field :resume, "SessionResumeCapabilities", default_on_error: true
      field :close, "SessionCloseCapabilities", default_on_error: true
    end

    class SessionListCapabilities < Base; end

    class SessionDeleteCapabilities < Base; end

    class SessionAdditionalDirectoriesCapabilities < Base; end

    class SessionForkCapabilities < Base; end

    class SessionResumeCapabilities < Base; end

    class SessionCloseCapabilities < Base; end

    class AgentAuthCapabilities < Base
      field :logout, "LogoutCapabilities", default_on_error: true
    end

    class LogoutCapabilities < Base; end

    class ProvidersCapabilities < Base; end

    class NesCapabilities < Base
      field :events, "NesEventCapabilities", default_on_error: true
      field :context, "NesContextCapabilities", default_on_error: true
    end

    class NesEventCapabilities < Base
      field :document, "NesDocumentEventCapabilities", default_on_error: true
    end

    class NesDocumentEventCapabilities < Base
      field :did_open, "NesDocumentDidOpenCapabilities", default_on_error: true
      field :did_change, "NesDocumentDidChangeCapabilities", default_on_error: true
      field :did_close, "NesDocumentDidCloseCapabilities", default_on_error: true
      field :did_save, "NesDocumentDidSaveCapabilities", default_on_error: true
      field :did_focus, "NesDocumentDidFocusCapabilities", default_on_error: true
    end

    class NesDocumentDidOpenCapabilities < Base; end

    class NesDocumentDidChangeCapabilities < Base
      field :sync_kind, "TextDocumentSyncKind", required: true
    end

    class NesDocumentDidCloseCapabilities < Base; end

    class NesDocumentDidSaveCapabilities < Base; end

    class NesDocumentDidFocusCapabilities < Base; end

    class NesContextCapabilities < Base
      field :recent_files, "NesRecentFilesCapabilities", default_on_error: true
      field :related_snippets, "NesRelatedSnippetsCapabilities", default_on_error: true
      field :edit_history, "NesEditHistoryCapabilities", default_on_error: true
      field :user_actions, "NesUserActionsCapabilities", default_on_error: true
      field :open_files, "NesOpenFilesCapabilities", default_on_error: true
      field :diagnostics, "NesDiagnosticsCapabilities", default_on_error: true
    end

    class NesRecentFilesCapabilities < Base
      field :max_count, :integer, default_on_error: true
    end

    class NesRelatedSnippetsCapabilities < Base; end

    class NesEditHistoryCapabilities < Base
      field :max_count, :integer, default_on_error: true
    end

    class NesUserActionsCapabilities < Base
      field :max_count, :integer, default_on_error: true
    end

    class NesOpenFilesCapabilities < Base; end

    class NesDiagnosticsCapabilities < Base; end

    class AuthMethodTerminal < Base
      field :id, "AuthMethodId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
      field :args, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :env, Types::Map.new(:string), default_on_error: true
    end

    class AuthMethodAgent < Base
      field :id, "AuthMethodId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
    end

    class Implementation < Base
      field :name, :string, required: true
      field :title, :string, default_on_error: true
      field :version, :string, required: true
    end

    class AuthenticateResponse < Base; end

    class ListProvidersResponse < Base
      field :providers, Types::List.new("ProviderInfo"), required: true
    end

    class ProviderInfo < Base
      field :provider_id, "ProviderId", required: true
      field :supported, Types::List.new("LlmProtocol", skip_invalid: true), required: true, default_on_error: true
      field :required, :boolean, required: true
      field :current, "ProviderCurrentConfig"
    end

    class ProviderCurrentConfig < Base
      field :api_type, "LlmProtocol", required: true
      field :base_url, :string, required: true
    end

    class SetProviderResponse < Base; end

    class DisableProviderResponse < Base; end

    class LogoutResponse < Base; end

    class NewSessionResponse < Base
      field :session_id, "SessionId", required: true
      field :modes, "SessionModeState", default_on_error: true
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), default_on_error: true
    end

    class SessionModeState < Base
      field :current_mode_id, "SessionModeId", required: true
      field :available_modes, Types::List.new("SessionMode", skip_invalid: true), required: true, default_on_error: true
    end

    class SessionMode < Base
      field :id, "SessionModeId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
    end

    class SessionConfigSelectOption < Base
      field :value, "SessionConfigValueId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
    end

    class SessionConfigSelectGroup < Base
      field :group, "SessionConfigGroupId", required: true
      field :name, :string, required: true
      field :options, Types::List.new("SessionConfigSelectOption", skip_invalid: true), required: true, default_on_error: true
    end

    class SessionConfigSelect < Base
      field :current_value, "SessionConfigValueId", required: true
      field :options, "SessionConfigSelectOptions", required: true
    end

    class SessionConfigBoolean < Base
      field :current_value, :boolean, required: true
    end

    class LoadSessionResponse < Base
      field :modes, "SessionModeState", default_on_error: true
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), default_on_error: true
    end

    class ListSessionsResponse < Base
      field :sessions, Types::List.new("SessionInfo", skip_invalid: true), required: true, default_on_error: true
      field :next_cursor, :string, default_on_error: true
    end

    class SessionInfo < Base
      field :session_id, "SessionId", required: true
      field :cwd, :string, required: true
      field :additional_directories, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :title, :string, default_on_error: true
      field :updated_at, :string, default_on_error: true
    end

    class DeleteSessionResponse < Base; end

    class ForkSessionResponse < Base
      field :session_id, "SessionId", required: true
      field :modes, "SessionModeState", default_on_error: true
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), default_on_error: true
    end

    class ResumeSessionResponse < Base
      field :modes, "SessionModeState", default_on_error: true
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), default_on_error: true
    end

    class CloseSessionResponse < Base; end

    class SetSessionModeResponse < Base; end

    class SetSessionConfigOptionResponse < Base
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), required: true, default_on_error: true
    end

    class PromptResponse < Base
      field :stop_reason, "StopReason", required: true
      field :usage, "Usage", default_on_error: true
    end

    class Usage < Base
      field :total_tokens, :integer, required: true
      field :input_tokens, :integer, required: true
      field :output_tokens, :integer, required: true
      field :thought_tokens, :integer, default_on_error: true
      field :cached_read_tokens, :integer, default_on_error: true
      field :cached_write_tokens, :integer, default_on_error: true
    end

    class StartNesResponse < Base
      field :session_id, "SessionId", required: true
    end

    class SuggestNesResponse < Base
      field :suggestions, Types::List.new("NesSuggestion"), required: true
    end

    class NesTextEdit < Base
      field :range, "Range", required: true
      field :new_text, :string, required: true
    end

    class Range < Base
      field :start, "Position", required: true
      field :end, "Position", required: true
    end

    class Position < Base
      field :line, :integer, required: true
      field :character, :integer, required: true
    end

    class NesEditSuggestion < Base
      field :id, "NesSuggestionId", required: true
      field :uri, :string, required: true
      field :edits, Types::List.new("NesTextEdit"), required: true
      field :cursor_position, "Position", default_on_error: true
    end

    class NesJumpSuggestion < Base
      field :id, "NesSuggestionId", required: true
      field :uri, :string, required: true
      field :position, "Position", required: true
    end

    class NesRenameSuggestion < Base
      field :id, "NesSuggestionId", required: true
      field :uri, :string, required: true
      field :position, "Position", required: true
      field :new_name, :string, required: true
    end

    class NesSearchAndReplaceSuggestion < Base
      field :id, "NesSuggestionId", required: true
      field :uri, :string, required: true
      field :search, :string, required: true
      field :replace, :string, required: true
      field :is_regex, :boolean
    end

    class CloseNesResponse < Base; end

    class Error < Base
      field :code, "ErrorCode", required: true
      field :message, :string, required: true
      field :data, :any, default_on_error: true
    end

    class SessionNotification < Base
      field :session_id, "SessionId", required: true
      field :update, "SessionUpdate", required: true
    end

    class ContentChunk < Base
      field :content, "ContentBlock", required: true
      field :message_id, "MessageId", default_on_error: true
    end

    class ToolCall < Base
      field :tool_call_id, "ToolCallId", required: true
      field :title, :string, required: true
      field :name, :string, default_on_error: true
      field :kind, "ToolKind", default_on_error: true
      field :status, "ToolCallStatus", default_on_error: true
      field :content, Types::List.new("ToolCallContent", skip_invalid: true), default_on_error: true
      field :locations, Types::List.new("ToolCallLocation", skip_invalid: true), default_on_error: true
      field :raw_input, :any, default_on_error: true
      field :raw_output, :any, default_on_error: true
    end

    class PlanEntry < Base
      field :content, :string, required: true
      field :priority, "PlanEntryPriority", required: true
      field :status, "PlanEntryStatus", required: true
    end

    class Plan < Base
      field :entries, Types::List.new("PlanEntry", skip_invalid: true), required: true, default_on_error: true
    end

    class PlanItems < Base
      field :plan_id, "PlanId", required: true
      field :entries, Types::List.new("PlanEntry", skip_invalid: true), required: true, default_on_error: true
    end

    class PlanFile < Base
      field :plan_id, "PlanId", required: true
      field :uri, :string, required: true
    end

    class PlanMarkdown < Base
      field :plan_id, "PlanId", required: true
      field :content, :string, required: true
    end

    class PlanUpdate < Base
      field :plan, "PlanUpdateContent", required: true
    end

    class PlanRemoved < Base
      field :plan_id, "PlanId", required: true
    end

    class AvailableCommand < Base
      field :name, :string, required: true
      field :description, :string, required: true
      field :input, "AvailableCommandInput", default_on_error: true
    end

    class UnstructuredCommandInput < Base
      field :hint, :string, required: true
    end

    class AvailableCommandsUpdateBase < Base
      field :available_commands, Types::List.new("AvailableCommand", skip_invalid: true), required: true, default_on_error: true
    end

    class CurrentModeUpdateBase < Base
      field :current_mode_id, "SessionModeId", required: true
    end

    class ConfigOptionUpdateBase < Base
      field :config_options, Types::List.new("SessionConfigOption", skip_invalid: true), required: true, default_on_error: true
    end

    class SessionInfoUpdateBase < Base
      field :title, :string, default_on_error: true
      field :updated_at, :string, default_on_error: true
    end

    class Cost < Base
      field :amount, :number, required: true
      field :currency, :string, required: true
    end

    class UsageUpdateBase < Base
      field :used, :integer, required: true
      field :size, :integer, required: true
      field :cost, "Cost", default_on_error: true
    end

    class CompactionUpdate < Base
      field :compaction_id, "CompactionId", required: true
      field :status, "CompactionStatus", required: true
      field :summary, Types::List.new("ContentBlock", skip_invalid: true), default_on_error: true
      field :error, :string, default_on_error: true
    end

    class CompactionSummaryChunk < Base
      field :compaction_id, "CompactionId", required: true
      field :content, "ContentBlock", required: true
    end

    class CompleteElicitationNotification < Base
      field :elicitation_id, "ElicitationId", required: true
    end

    class MessageMcpNotification < Base
      field :connection_id, "McpConnectionId", required: true
      field :method_name, :string, key: "method", required: true
      field :params, :object, default_on_error: true
    end

    class InitializeRequest < Base
      field :protocol_version, "ProtocolVersion", required: true
      field :client_capabilities, "ClientCapabilities", default: {"fs" => {"readTextFile" => false, "writeTextFile" => false}, "terminal" => false, "auth" => {"terminal" => false}}, default_on_error: true
      field :client_info, "Implementation", default_on_error: true
    end

    class ClientCapabilities < Base
      field :fs, "FileSystemCapabilities", default: {"readTextFile" => false, "writeTextFile" => false}, default_on_error: true
      field :terminal, :boolean, default: false, default_on_error: true
      field :session, "ClientSessionCapabilities", default_on_error: true
      field :plan, "PlanCapabilities", default_on_error: true
      field :auth, "AuthCapabilities", default: {"terminal" => false}, default_on_error: true
      field :elicitation, "ElicitationCapabilities", default_on_error: true
      field :nes, "ClientNesCapabilities", default_on_error: true
      field :position_encodings, Types::List.new("PositionEncodingKind", skip_invalid: true), default_on_error: true
    end

    class FileSystemCapabilities < Base
      field :read_text_file, :boolean, default: false, default_on_error: true
      field :write_text_file, :boolean, default: false, default_on_error: true
    end

    class ClientSessionCapabilities < Base
      field :compaction, "CompactionCapabilities", default_on_error: true
      field :config_options, "SessionConfigOptionsCapabilities", default_on_error: true
    end

    class CompactionCapabilities < Base; end

    class SessionConfigOptionsCapabilities < Base
      field :boolean, "BooleanConfigOptionCapabilities", default_on_error: true
    end

    class BooleanConfigOptionCapabilities < Base; end

    class PlanCapabilities < Base; end

    class AuthCapabilities < Base
      field :terminal, :boolean, default: false, default_on_error: true
    end

    class ElicitationCapabilities < Base
      field :form, "ElicitationFormCapabilities", default_on_error: true
      field :url, "ElicitationUrlCapabilities", default_on_error: true
    end

    class ElicitationFormCapabilities < Base; end

    class ElicitationUrlCapabilities < Base; end

    class ClientNesCapabilities < Base
      field :jump, "NesJumpCapabilities", default_on_error: true
      field :rename, "NesRenameCapabilities", default_on_error: true
      field :search_and_replace, "NesSearchAndReplaceCapabilities", default_on_error: true
    end

    class NesJumpCapabilities < Base; end

    class NesRenameCapabilities < Base; end

    class NesSearchAndReplaceCapabilities < Base; end

    class AuthenticateRequest < Base
      field :method_id, "AuthMethodId", required: true
    end

    class ListProvidersRequest < Base; end

    class SetProviderRequest < Base
      field :provider_id, "ProviderId", required: true
      field :api_type, "LlmProtocol", required: true
      field :base_url, :string, required: true
      field :headers, Types::Map.new(:string)
    end

    class DisableProviderRequest < Base
      field :provider_id, "ProviderId", required: true
    end

    class LogoutRequest < Base; end

    class NewSessionRequest < Base
      field :cwd, :string, required: true
      field :additional_directories, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :mcp_servers, Types::List.new("McpServer", skip_invalid: true), required: true, default_on_error: true
    end

    class HttpHeader < Base
      field :name, :string, required: true
      field :value, :string, required: true
    end

    class McpServerHttp < Base
      field :name, :string, required: true
      field :url, :string, required: true
      field :headers, Types::List.new("HttpHeader"), required: true
    end

    class McpServerSse < Base
      field :name, :string, required: true
      field :url, :string, required: true
      field :headers, Types::List.new("HttpHeader"), required: true
    end

    class McpServerAcp < Base
      field :name, :string, required: true
      field :server_id, "McpServerAcpId", required: true
    end

    class McpServerStdio < Base
      field :name, :string, required: true
      field :command, :string, required: true
      field :args, Types::List.new(:string), required: true
      field :env, Types::List.new("EnvVariable"), required: true
    end

    class LoadSessionRequest < Base
      field :mcp_servers, Types::List.new("McpServer", skip_invalid: true), required: true, default_on_error: true
      field :cwd, :string, required: true
      field :additional_directories, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :session_id, "SessionId", required: true
    end

    class ListSessionsRequest < Base
      field :cwd, :string
      field :cursor, :string
    end

    class DeleteSessionRequest < Base
      field :session_id, "SessionId", required: true
    end

    class ForkSessionRequest < Base
      field :session_id, "SessionId", required: true
      field :cwd, :string, required: true
      field :additional_directories, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :mcp_servers, Types::List.new("McpServer", skip_invalid: true), default_on_error: true
    end

    class ResumeSessionRequest < Base
      field :session_id, "SessionId", required: true
      field :cwd, :string, required: true
      field :additional_directories, Types::List.new(:string, skip_invalid: true), default_on_error: true
      field :mcp_servers, Types::List.new("McpServer", skip_invalid: true), default_on_error: true
    end

    class CloseSessionRequest < Base
      field :session_id, "SessionId", required: true
    end

    class SetSessionModeRequest < Base
      field :session_id, "SessionId", required: true
      field :mode_id, "SessionModeId", required: true
    end

    class PromptRequest < Base
      field :session_id, "SessionId", required: true
      field :prompt, Types::List.new("ContentBlock"), required: true
    end

    class StartNesRequest < Base
      field :workspace_uri, :string, default_on_error: true
      field :workspace_folders, Types::List.new("WorkspaceFolder")
      field :repository, "NesRepository", default_on_error: true
    end

    class WorkspaceFolder < Base
      field :uri, :string, required: true
      field :name, :string, required: true
    end

    class NesRepository < Base
      field :name, :string, required: true
      field :owner, :string, required: true
      field :remote_url, :string, required: true
    end

    class SuggestNesRequest < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
      field :version, :integer, required: true
      field :position, "Position", required: true
      field :selection, "Range"
      field :trigger_kind, "NesTriggerKind", required: true
      field :context, "NesSuggestContext"
    end

    class NesSuggestContext < Base
      field :recent_files, Types::List.new("NesRecentFile")
      field :related_snippets, Types::List.new("NesRelatedSnippet")
      field :edit_history, Types::List.new("NesEditHistoryEntry")
      field :user_actions, Types::List.new("NesUserAction")
      field :open_files, Types::List.new("NesOpenFile")
      field :diagnostics, Types::List.new("NesDiagnostic")
    end

    class NesRecentFile < Base
      field :uri, :string, required: true
      field :language_id, :string, required: true
      field :text, :string, required: true
    end

    class NesRelatedSnippet < Base
      field :uri, :string, required: true
      field :excerpts, Types::List.new("NesExcerpt"), required: true
    end

    class NesExcerpt < Base
      field :start_line, :integer, required: true
      field :end_line, :integer, required: true
      field :text, :string, required: true
    end

    class NesEditHistoryEntry < Base
      field :uri, :string, required: true
      field :diff, :string, required: true
    end

    class NesUserAction < Base
      field :action, :string, required: true
      field :uri, :string, required: true
      field :position, "Position", required: true
      field :timestamp_ms, :integer, required: true
    end

    class NesOpenFile < Base
      field :uri, :string, required: true
      field :language_id, :string, required: true
      field :visible_range, "Range", default_on_error: true
      field :last_focused_ms, :integer, default_on_error: true
    end

    class NesDiagnostic < Base
      field :uri, :string, required: true
      field :range, "Range", required: true
      field :severity, "NesDiagnosticSeverity", required: true
      field :message, :string, required: true
    end

    class CloseNesRequest < Base
      field :session_id, "SessionId", required: true
    end

    class WriteTextFileResponse < Base; end

    class ReadTextFileResponse < Base
      field :content, :string, required: true
    end

    class RequestPermissionResponse < Base
      field :outcome, "RequestPermissionOutcome", required: true
    end

    class SelectedPermissionOutcome < Base
      field :option_id, "PermissionOptionId", required: true
    end

    class CreateTerminalResponse < Base
      field :terminal_id, "TerminalId", required: true
    end

    class TerminalOutputResponse < Base
      field :output, :string, required: true
      field :truncated, :boolean, required: true
      field :exit_status, "TerminalExitStatus", default_on_error: true
    end

    class TerminalExitStatus < Base
      field :exit_code, :integer, default_on_error: true
      field :signal, :string, default_on_error: true
    end

    class ReleaseTerminalResponse < Base; end

    class WaitForTerminalExitResponse < Base
      field :exit_code, :integer, default_on_error: true
      field :signal, :string, default_on_error: true
    end

    class KillTerminalResponse < Base; end

    class ElicitationAcceptAction < Base
      field :content, Types::Map.new("ElicitationContentValue")
    end

    class ConnectMcpResponse < Base
      field :connection_id, "McpConnectionId", required: true
    end

    class DisconnectMcpResponse < Base; end

    class CancelNotification < Base
      field :session_id, "SessionId", required: true
    end

    class DidOpenDocumentNotification < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
      field :language_id, :string, required: true
      field :version, :integer, required: true
      field :text, :string, required: true
    end

    class DidChangeDocumentNotification < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
      field :version, :integer, required: true
      field :content_changes, Types::List.new("TextDocumentContentChangeEvent", skip_invalid: true), required: true, default_on_error: true
    end

    class TextDocumentContentChangeEvent < Base
      field :range, "Range"
      field :text, :string, required: true
    end

    class DidCloseDocumentNotification < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
    end

    class DidSaveDocumentNotification < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
    end

    class DidFocusDocumentNotification < Base
      field :session_id, "SessionId", required: true
      field :uri, :string, required: true
      field :version, :integer, required: true
      field :position, "Position", required: true
      field :visible_range, "Range", required: true
    end

    class AcceptNesNotification < Base
      field :session_id, "SessionId", required: true
      field :id, "NesSuggestionId", required: true
    end

    class RejectNesNotification < Base
      field :session_id, "SessionId", required: true
      field :id, "NesSuggestionId", required: true
      field :reason, "NesRejectReason", default_on_error: true
    end

    class CancelRequestNotification < Base
      field :request_id, "RequestId", required: true
    end

    class ContentToolCallContent < Content
      field :type, :string, const: "content"
    end

    class FileEditToolCallContent < Diff
      field :type, :string, const: "diff"
    end

    class TerminalToolCallContent < Terminal
      field :type, :string, const: "terminal"
    end

    class TextContentBlock < TextContent
      field :type, :string, const: "text"
    end

    class ImageContentBlock < ImageContent
      field :type, :string, const: "image"
    end

    class AudioContentBlock < AudioContent
      field :type, :string, const: "audio"
    end

    class ResourceContentBlock < ResourceLink
      field :type, :string, const: "resource_link"
    end

    class EmbeddedResourceContentBlock < EmbeddedResource
      field :type, :string, const: "resource"
    end

    class CreateFormSessionElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, const: "form"
      field :requested_schema, "ElicitationSchema", required: true
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class CreateFormRequestElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, const: "form"
      field :requested_schema, "ElicitationSchema", required: true
      field :request_id, "RequestId", required: true
    end

    class CreateUrlSessionElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, const: "url"
      field :elicitation_id, "ElicitationId", required: true
      field :url, :string, required: true
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class CreateUrlRequestElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, const: "url"
      field :elicitation_id, "ElicitationId", required: true
      field :url, :string, required: true
      field :request_id, "RequestId", required: true
    end

    class CreateOtherSessionElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, required: true
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class CreateOtherRequestElicitationRequest < Base
      field :message, :string, required: true
      field :mode, :string, required: true
      field :request_id, "RequestId", required: true
    end

    class ElicitationStringPropertySchema < StringPropertySchema
      field :type, :string, const: "string"
    end

    class ElicitationNumberPropertySchema < NumberPropertySchema
      field :type, :string, const: "number"
    end

    class ElicitationIntegerPropertySchema < IntegerPropertySchema
      field :type, :string, const: "integer"
    end

    class ElicitationBooleanPropertySchema < BooleanPropertySchema
      field :type, :string, const: "boolean"
    end

    class ElicitationMultiSelectPropertySchema < MultiSelectPropertySchema
      field :type, :string, const: "array"
    end

    class ElicitationOtherPropertySchema < Base
      field :type, :string, required: true
    end

    class StringMultiSelectItems < StringMultiSelectItemsBase
      field :type, :string, const: "string"
    end

    class OtherMultiSelectItems < Base
      field :type, :string, required: true
    end

    class ElicitationFormSessionMode < Base
      field :requested_schema, "ElicitationSchema", required: true
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class ElicitationFormRequestMode < Base
      field :requested_schema, "ElicitationSchema", required: true
      field :request_id, "RequestId", required: true
    end

    class ElicitationUrlSessionMode < Base
      field :elicitation_id, "ElicitationId", required: true
      field :url, :string, required: true
      field :session_id, "SessionId", required: true
      field :tool_call_id, "ToolCallId", default_on_error: true
    end

    class ElicitationUrlRequestMode < Base
      field :elicitation_id, "ElicitationId", required: true
      field :url, :string, required: true
      field :request_id, "RequestId", required: true
    end

    class TerminalAuthMethod < AuthMethodTerminal
      field :type, :string, const: "terminal"
    end

    class SessionConfigOptionSelect < Base
      field :id, "SessionConfigId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
      field :category, "SessionConfigOptionCategory", default_on_error: true
      field :type, :string, const: "select"
      field :current_value, "SessionConfigValueId", required: true
      field :options, "SessionConfigSelectOptions", required: true
    end

    class SessionConfigOptionBoolean < Base
      field :id, "SessionConfigId", required: true
      field :name, :string, required: true
      field :description, :string, default_on_error: true
      field :category, "SessionConfigOptionCategory", default_on_error: true
      field :type, :string, const: "boolean"
      field :current_value, :boolean, required: true
    end

    class NesEditSuggestionVariant < NesEditSuggestion
      field :kind, :string, const: "edit"
    end

    class NesJumpSuggestionVariant < NesJumpSuggestion
      field :kind, :string, const: "jump"
    end

    class NesRenameSuggestionVariant < NesRenameSuggestion
      field :kind, :string, const: "rename"
    end

    class NesSearchAndReplaceSuggestionVariant < NesSearchAndReplaceSuggestion
      field :kind, :string, const: "searchAndReplace"
    end

    class UserMessageChunk < ContentChunk
      field :session_update, :string, const: "user_message_chunk"
    end

    class AgentMessageChunk < ContentChunk
      field :session_update, :string, const: "agent_message_chunk"
    end

    class AgentThoughtChunk < ContentChunk
      field :session_update, :string, const: "agent_thought_chunk"
    end

    class ToolCallStart < ToolCall
      field :session_update, :string, const: "tool_call"
    end

    class ToolCallProgress < ToolCallUpdate
      field :session_update, :string, const: "tool_call_update"
    end

    class AgentPlanUpdate < Plan
      field :session_update, :string, const: "plan"
    end

    class AgentPlanContentUpdate < PlanUpdate
      field :session_update, :string, const: "plan_update"
    end

    class AgentPlanRemovedUpdate < PlanRemoved
      field :session_update, :string, const: "plan_removed"
    end

    class AvailableCommandsUpdate < AvailableCommandsUpdateBase
      field :session_update, :string, const: "available_commands_update"
    end

    class CurrentModeUpdate < CurrentModeUpdateBase
      field :session_update, :string, const: "current_mode_update"
    end

    class ConfigOptionUpdate < ConfigOptionUpdateBase
      field :session_update, :string, const: "config_option_update"
    end

    class SessionInfoUpdate < SessionInfoUpdateBase
      field :session_update, :string, const: "session_info_update"
    end

    class UsageUpdate < UsageUpdateBase
      field :session_update, :string, const: "usage_update"
    end

    class SessionUpdateCompactionUpdate < CompactionUpdate
      field :session_update, :string, const: "compaction_update"
    end

    class SessionUpdateCompactionSummaryChunk < CompactionSummaryChunk
      field :session_update, :string, const: "compaction_summary_chunk"
    end

    class PlanUpdateItems < PlanItems
      field :type, :string, const: "items"
    end

    class PlanUpdateFile < PlanFile
      field :type, :string, const: "file"
    end

    class PlanUpdateMarkdown < PlanMarkdown
      field :type, :string, const: "markdown"
    end

    class HttpMcpServer < McpServerHttp
      field :type, :string, const: "http"
    end

    class SseMcpServer < McpServerSse
      field :type, :string, const: "sse"
    end

    class AcpMcpServer < McpServerAcp
      field :type, :string, const: "acp"
    end

    class SetSessionConfigOptionBooleanRequest < Base
      field :session_id, "SessionId", required: true
      field :config_id, "SessionConfigId", required: true
      field :value, :boolean, required: true
      field :type, :string, const: "boolean"
    end

    class SetSessionConfigOptionSelectRequest < Base
      field :session_id, "SessionId", required: true
      field :config_id, "SessionConfigId", required: true
      field :value, "SessionConfigValueId", required: true
    end

    class DeniedOutcome < Base
      field :outcome, :string, const: "cancelled"
    end

    class AllowedOutcome < SelectedPermissionOutcome
      field :outcome, :string, const: "selected"
    end

    class AcceptElicitationResponse < ElicitationAcceptAction
      field :action, :string, const: "accept"
    end

    class DeclineElicitationResponse < Base
      field :action, :string, const: "decline"
    end

    class CancelElicitationResponse < Base
      field :action, :string, const: "cancel"
    end

    class OtherElicitationResponse < Base
      field :action, :string, required: true
    end

    RequestId = Types::ANY
    SessionId = Types::STRING
    ToolCallId = Types::STRING
    ToolKind = Types::Enum.new(["read", "edit", "delete", "move", "search", "execute", "think", "fetch", "switch_mode", "other"])
    ToolCallStatus = Types::Enum.new(["pending", "in_progress", "completed", "failed"])
    ToolCallContent = Types::Union.new(tag: "type", tagged: { "content" => ["ContentToolCallContent"], "diff" => ["FileEditToolCallContent"], "terminal" => ["TerminalToolCallContent"] })
    ContentBlock = Types::Union.new(tag: "type", tagged: { "text" => ["TextContentBlock"], "image" => ["ImageContentBlock"], "audio" => ["AudioContentBlock"], "resource_link" => ["ResourceContentBlock"], "resource" => ["EmbeddedResourceContentBlock"] })
    Role = Types::Enum.new(["assistant", "user"])
    EmbeddedResourceResource = Types::Union.new(untagged: ["TextResourceContents", "BlobResourceContents"])
    TerminalId = Types::STRING
    PermissionOptionId = Types::STRING
    PermissionOptionKind = Types::Enum.new(["allow_once", "allow_always", "reject_once", "reject_always"])
    CreateElicitationRequest = Types::Union.new(tag: "mode", tagged: { "form" => ["CreateFormSessionElicitationRequest", "CreateFormRequestElicitationRequest"], "url" => ["CreateUrlSessionElicitationRequest", "CreateUrlRequestElicitationRequest"] }, untagged: ["CreateOtherSessionElicitationRequest", "CreateOtherRequestElicitationRequest"])
    ElicitationSchemaType = Types::Enum.new(["object"])
    ElicitationPropertySchema = Types::Union.new(tag: "type", tagged: { "string" => ["ElicitationStringPropertySchema"], "number" => ["ElicitationNumberPropertySchema"], "integer" => ["ElicitationIntegerPropertySchema"], "boolean" => ["ElicitationBooleanPropertySchema"], "array" => ["ElicitationMultiSelectPropertySchema"] }, untagged: ["ElicitationOtherPropertySchema"])
    StringFormat = Types::Enum.new(["email", "uri", "date", "date-time"])
    MultiSelectItems = Types::Union.new(tag: "type", tagged: { "string" => ["StringMultiSelectItems"] }, untagged: ["OtherMultiSelectItems", "TitledMultiSelectItems"])
    ElicitationFormMode = Types::Union.new(untagged: ["ElicitationFormSessionMode", "ElicitationFormRequestMode"])
    ElicitationId = Types::STRING
    ElicitationUrlMode = Types::Union.new(untagged: ["ElicitationUrlSessionMode", "ElicitationUrlRequestMode"])
    McpServerAcpId = Types::STRING
    McpConnectionId = Types::STRING
    ExtRequest = Types::ANY
    ProtocolVersion = Types::PROTOCOL_VERSION
    TextDocumentSyncKind = Types::Enum.new(["full", "incremental"])
    PositionEncodingKind = Types::Enum.new(["utf-16", "utf-32", "utf-8"])
    AuthMethod = Types::Union.new(tag: "type", tagged: { "terminal" => ["TerminalAuthMethod"] }, untagged: ["AuthMethodAgent"])
    AuthMethodId = Types::STRING
    ProviderId = Types::STRING
    LlmProtocol = Types::Enum.new(["anthropic", "openai", "azure", "vertex", "bedrock"], open: true)
    SessionModeId = Types::STRING
    SessionConfigOption = Types::Union.new(tag: "type", tagged: { "select" => ["SessionConfigOptionSelect"], "boolean" => ["SessionConfigOptionBoolean"] })
    SessionConfigId = Types::STRING
    SessionConfigOptionCategory = Types::Enum.new(["mode", "model", "model_config", "thought_level"], open: true)
    SessionConfigValueId = Types::STRING
    SessionConfigSelectOptions = Types::Union.new(untagged: [Types::List.new("SessionConfigSelectOption"), Types::List.new("SessionConfigSelectGroup")])
    SessionConfigGroupId = Types::STRING
    StopReason = Types::Enum.new(["end_turn", "max_tokens", "max_turn_requests", "refusal", "cancelled"])
    NesSuggestion = Types::Union.new(tag: "kind", tagged: { "edit" => ["NesEditSuggestionVariant"], "jump" => ["NesJumpSuggestionVariant"], "rename" => ["NesRenameSuggestionVariant"], "searchAndReplace" => ["NesSearchAndReplaceSuggestionVariant"] })
    NesSuggestionId = Types::STRING
    ExtResponse = Types::ANY
    MessageMcpResponse = Types::ANY
    ErrorCode = Types::INTEGER
    SessionUpdate = Types::Union.new(tag: "sessionUpdate", tagged: { "user_message_chunk" => ["UserMessageChunk"], "agent_message_chunk" => ["AgentMessageChunk"], "agent_thought_chunk" => ["AgentThoughtChunk"], "tool_call" => ["ToolCallStart"], "tool_call_update" => ["ToolCallProgress"], "plan" => ["AgentPlanUpdate"], "plan_update" => ["AgentPlanContentUpdate"], "plan_removed" => ["AgentPlanRemovedUpdate"], "available_commands_update" => ["AvailableCommandsUpdate"], "current_mode_update" => ["CurrentModeUpdate"], "config_option_update" => ["ConfigOptionUpdate"], "session_info_update" => ["SessionInfoUpdate"], "usage_update" => ["UsageUpdate"], "compaction_update" => ["SessionUpdateCompactionUpdate"], "compaction_summary_chunk" => ["SessionUpdateCompactionSummaryChunk"] })
    MessageId = Types::STRING
    PlanEntryPriority = Types::Enum.new(["high", "medium", "low"])
    PlanEntryStatus = Types::Enum.new(["pending", "in_progress", "completed"])
    PlanUpdateContent = Types::Union.new(tag: "type", tagged: { "items" => ["PlanUpdateItems"], "file" => ["PlanUpdateFile"], "markdown" => ["PlanUpdateMarkdown"] })
    PlanId = Types::STRING
    AvailableCommandInput = Types::Union.new(untagged: ["UnstructuredCommandInput"])
    CompactionId = Types::STRING
    CompactionStatus = Types::Enum.new(["in_progress", "completed", "failed", "cancelled"], open: true)
    ExtNotification = Types::ANY
    McpServer = Types::Union.new(tag: "type", tagged: { "http" => ["HttpMcpServer"], "sse" => ["SseMcpServer"], "acp" => ["AcpMcpServer"] }, untagged: ["McpServerStdio"])
    SetSessionConfigOptionRequest = Types::Union.new(tag: "type", tagged: { "boolean" => ["SetSessionConfigOptionBooleanRequest"] }, untagged: ["SetSessionConfigOptionSelectRequest"])
    NesTriggerKind = Types::Enum.new(["automatic", "diagnostic", "manual"])
    NesDiagnosticSeverity = Types::Enum.new(["error", "warning", "information", "hint"])
    RequestPermissionOutcome = Types::Union.new(tag: "outcome", tagged: { "cancelled" => ["DeniedOutcome"], "selected" => ["AllowedOutcome"] })
    CreateElicitationResponse = Types::Union.new(tag: "action", tagged: { "accept" => ["AcceptElicitationResponse"], "decline" => ["DeclineElicitationResponse"], "cancel" => ["CancelElicitationResponse"] }, untagged: ["OtherElicitationResponse"])
    ElicitationContentValue = Types::ANY
    NesRejectReason = Types::Enum.new(["rejected", "ignored", "replaced", "cancelled"])
  end
end
