# frozen_string_literal: true

require_relative "connection"
require_relative "meta"
require_relative "router"
require_relative "schema"

module ACP
  module Client
    class Connection
      DEFAULT_DRAIN_TIMEOUT = 1.0

      attr_reader :conn, :handler

      def initialize(handler, transport, drain_timeout: DEFAULT_DRAIN_TIMEOUT, **connection_options)
        @handler = handler
        @drain_timeout = drain_timeout
        router = self.class.build_router(handler)
        @conn = ACP::Connection.new(router.method(:call), transport, **connection_options)
        handler.on_connect(self) if handler.respond_to?(:on_connect)
      end

      def self.build_router(client)
        router = Router.new

        router.route_request(CLIENT_METHODS["fs_write_text_file"], Schema::WriteTextFileRequest, client,
                             :write_text_file, normalize: true)
        router.route_request(CLIENT_METHODS["fs_read_text_file"], Schema::ReadTextFileRequest, client,
                             :read_text_file)
        router.route_request(CLIENT_METHODS["session_request_permission"], Schema::RequestPermissionRequest, client,
                             :request_permission)
        router.route_request(CLIENT_METHODS["terminal_create"], Schema::CreateTerminalRequest, client,
                             :create_terminal, optional: true)
        router.route_request(CLIENT_METHODS["terminal_output"], Schema::TerminalOutputRequest, client,
                             :terminal_output, optional: true)
        router.route_request(CLIENT_METHODS["terminal_release"], Schema::ReleaseTerminalRequest, client,
                             :release_terminal, optional: true, default_result: {}, normalize: true)
        router.route_request(CLIENT_METHODS["terminal_wait_for_exit"], Schema::WaitForTerminalExitRequest, client,
                             :wait_for_terminal_exit, optional: true)
        router.route_request(CLIENT_METHODS["terminal_kill"], Schema::KillTerminalRequest, client,
                             :kill_terminal, optional: true, default_result: {}, normalize: true)
        router.route_request(CLIENT_METHODS["elicitation_create"], Schema::CreateElicitationRequest, client,
                             :create_elicitation, normalize: true)
        router.route_request(CLIENT_METHODS["mcp_connect"], Schema::ConnectMcpRequest, client, :mcp_connect)
        router.route_request(CLIENT_METHODS["mcp_message"], Schema::MessageMcpRequest, client, :mcp_message)
        router.route_request(CLIENT_METHODS["mcp_disconnect"], Schema::DisconnectMcpRequest, client,
                             :mcp_disconnect, normalize: true)

        router.route_notification(CLIENT_METHODS["session_update"], Schema::SessionNotification, client,
                                  :session_update)
        router.route_notification(CLIENT_METHODS["elicitation_complete"], Schema::CompleteElicitationNotification,
                                  client, :complete_elicitation)

        router.on_extension_request do |name, params|
          raise RequestError.method_not_found("_#{name}") unless client.respond_to?(:ext_method)

          client.ext_method(name, params)
        end

        router.on_extension_notification do |name, params|
          client.ext_notification(name, params) if client.respond_to?(:ext_notification)
        end

        router
      end

      def listen
        @conn.listen
      end

      def start
        @conn.start
      end

      def join(timeout = nil)
        @conn.join(timeout)
      end

      def add_observer(callable = nil, &block)
        @conn.add_observer(callable, &block)
      end

      def close
        @conn.close
      end

      def closed?
        @conn.closed?
      end

      def initialize_agent(protocol_version: PROTOCOL_VERSION, client_capabilities: nil, client_info: nil, **meta)
        request(
          AGENT_METHODS["initialize"], Schema::InitializeRequest, Schema::InitializeResponse,
          protocol_version: protocol_version, client_capabilities: client_capabilities, client_info: client_info, **meta
        )
      end

      def authenticate(method_id:, **meta)
        request(AGENT_METHODS["authenticate"], Schema::AuthenticateRequest, Schema::AuthenticateResponse,
                method_id: method_id, **meta)
      end

      def new_session(cwd:, mcp_servers: [], additional_directories: nil, **meta)
        request(
          AGENT_METHODS["session_new"], Schema::NewSessionRequest, Schema::NewSessionResponse,
          cwd: cwd, mcp_servers: mcp_servers || [], additional_directories: additional_directories, **meta
        )
      end

      def load_session(cwd:, session_id:, mcp_servers: [], additional_directories: nil, **meta)
        request(
          AGENT_METHODS["session_load"], Schema::LoadSessionRequest, Schema::LoadSessionResponse,
          cwd: cwd, session_id: session_id, mcp_servers: mcp_servers || [],
          additional_directories: additional_directories, **meta
        )
      end

      def list_sessions(cwd: nil, cursor: nil, **meta)
        request(AGENT_METHODS["session_list"], Schema::ListSessionsRequest, Schema::ListSessionsResponse,
                cwd: cwd, cursor: cursor, **meta)
      end

      def fork_session(session_id:, cwd:, mcp_servers: nil, additional_directories: nil, **meta)
        request(
          AGENT_METHODS["session_fork"], Schema::ForkSessionRequest, Schema::ForkSessionResponse,
          session_id: session_id, cwd: cwd, mcp_servers: mcp_servers,
          additional_directories: additional_directories, **meta
        )
      end

      def resume_session(session_id:, cwd:, mcp_servers: nil, additional_directories: nil, **meta)
        request(
          AGENT_METHODS["session_resume"], Schema::ResumeSessionRequest, Schema::ResumeSessionResponse,
          session_id: session_id, cwd: cwd, mcp_servers: mcp_servers,
          additional_directories: additional_directories, **meta
        )
      end

      def close_session(session_id:, **meta)
        request(AGENT_METHODS["session_close"], Schema::CloseSessionRequest, Schema::CloseSessionResponse,
                session_id: session_id, **meta)
      end

      def delete_session(session_id:, **meta)
        request(AGENT_METHODS["session_delete"], Schema::DeleteSessionRequest, Schema::DeleteSessionResponse,
                session_id: session_id, **meta)
      end

      def set_session_mode(session_id:, mode_id:, **meta)
        request(AGENT_METHODS["session_set_mode"], Schema::SetSessionModeRequest, Schema::SetSessionModeResponse,
                session_id: session_id, mode_id: mode_id, **meta)
      end

      def set_session_config_option(session_id:, config_id:, value:, **meta)
        request_class = if [true, false].include?(value)
                          Schema::SetSessionConfigOptionBooleanRequest
                        else
                          Schema::SetSessionConfigOptionSelectRequest
                        end
        request(
          AGENT_METHODS["session_set_config_option"], request_class, Schema::SetSessionConfigOptionResponse,
          session_id: session_id, config_id: config_id, value: value, **meta
        )
      end

      # Short alias for the same wire method (session/set_config_option).
      alias set_config_option set_session_config_option

      def prompt(session_id:, prompt:, **meta)
        request(AGENT_METHODS["session_prompt"], Schema::PromptRequest, Schema::PromptResponse,
                session_id: session_id, prompt: prompt, **meta)
      ensure
        drain_notifications
      end

      def cancel(session_id:, **meta)
        notify(AGENT_METHODS["session_cancel"], Schema::CancelNotification, session_id: session_id, **meta)
      end

      def logout(**meta)
        request(AGENT_METHODS["logout"], Schema::LogoutRequest, Schema::LogoutResponse, **meta)
      end

      def ext_method(name, params = {})
        @conn.send_request("_#{name}", params)
      end

      def ext_notification(name, params = {})
        @conn.send_notification("_#{name}", params)
      end

      def drain_notifications(timeout: @drain_timeout)
        @conn.drain_notifications(timeout: timeout)
      end

      private

      def request(method, request_class, response_class, **kwargs)
        payload = build(request_class, kwargs)
        result = @conn.send_request(method, payload)
        response_class.coerce(result || {})
      end

      def notify(method, request_class, **kwargs)
        @conn.send_notification(method, build(request_class, kwargs))
      end

      def build(request_class, kwargs)
        meta = kwargs.delete(:field_meta) || kwargs.delete(:meta)
        model = request_class.new(**kwargs.compact)
        model.field_meta = meta if meta
        model
      end
    end
  end
end
