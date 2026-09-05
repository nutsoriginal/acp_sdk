# frozen_string_literal: true

require_relative "connection"
require_relative "meta"
require_relative "router"
require_relative "schema"
require_relative "transport"
require_relative "wait"

module ACP
  module Agent
    class Connection
      attr_reader :conn, :agent

      def initialize(agent, transport, **connection_options)
        @agent = agent
        router = self.class.build_router(agent)
        @conn = ACP::Connection.new(router.method(:call), transport, **connection_options)
        agent.on_connect(self) if agent.respond_to?(:on_connect)
      end

      def self.build_router(agent)
        router = Router.new

        router.route_request(AGENT_METHODS["initialize"], Schema::InitializeRequest, agent, :initialize_acp)
        router.route_request(AGENT_METHODS["authenticate"], Schema::AuthenticateRequest, agent, :authenticate,
                             normalize: true)
        router.route_request(AGENT_METHODS["session_new"], Schema::NewSessionRequest, agent, :new_session)
        router.route_request(AGENT_METHODS["session_load"], Schema::LoadSessionRequest, agent, :load_session,
                             normalize: true)
        router.route_request(AGENT_METHODS["session_list"], Schema::ListSessionsRequest, agent, :list_sessions)
        router.route_request(AGENT_METHODS["session_fork"], Schema::ForkSessionRequest, agent, :fork_session)
        router.route_request(AGENT_METHODS["session_resume"], Schema::ResumeSessionRequest, agent, :resume_session)
        router.route_request(AGENT_METHODS["session_close"], Schema::CloseSessionRequest, agent, :close_session,
                             normalize: true)
        router.route_request(AGENT_METHODS["session_delete"], Schema::DeleteSessionRequest, agent, :delete_session,
                             normalize: true)
        router.route_request(AGENT_METHODS["session_set_mode"], Schema::SetSessionModeRequest, agent,
                             :set_session_mode, normalize: true)
        router.route_request(AGENT_METHODS["session_set_config_option"], Schema::SetSessionConfigOptionRequest, agent,
                             :set_session_config_option, :set_config_option, normalize: true)
        router.route_request(AGENT_METHODS["session_prompt"], Schema::PromptRequest, agent, :prompt)
        router.route_request(AGENT_METHODS["logout"], Schema::LogoutRequest, agent, :logout, normalize: true)
        router.route_request(AGENT_METHODS["providers_list"], Schema::ListProvidersRequest, agent, :list_providers)
        router.route_request(AGENT_METHODS["providers_set"], Schema::SetProviderRequest, agent, :set_provider,
                             normalize: true)
        router.route_request(AGENT_METHODS["providers_disable"], Schema::DisableProviderRequest, agent,
                             :disable_provider, normalize: true)
        router.route_request(AGENT_METHODS["mcp_message"], Schema::MessageMcpRequest, agent, :mcp_message)

        router.route_notification(AGENT_METHODS["session_cancel"], Schema::CancelNotification, agent,
                                  :cancel, :cancel_session)

        router.on_extension_request do |name, params|
          raise RequestError.method_not_found("_#{name}") unless agent.respond_to?(:ext_method)

          agent.ext_method(name, params)
        end

        router.on_extension_notification do |name, params|
          agent.ext_notification(name, params) if agent.respond_to?(:ext_notification)
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

      def session_update(session_id:, update:, **meta)
        notify(CLIENT_METHODS["session_update"], Schema::SessionNotification, session_id: session_id, update: update, **meta)
      end

      def request_permission(session_id:, tool_call:, options:, **meta)
        request(
          CLIENT_METHODS["session_request_permission"], Schema::RequestPermissionRequest,
          Schema::RequestPermissionResponse,
          session_id: session_id, tool_call: tool_call, options: options, **meta
        )
      end

      def read_text_file(session_id:, path:, line: nil, limit: nil, **meta)
        request(
          CLIENT_METHODS["fs_read_text_file"], Schema::ReadTextFileRequest, Schema::ReadTextFileResponse,
          session_id: session_id, path: path, line: line, limit: limit, **meta
        )
      end

      def write_text_file(session_id:, path:, content:, **meta)
        request_optional(
          CLIENT_METHODS["fs_write_text_file"], Schema::WriteTextFileRequest, Schema::WriteTextFileResponse,
          session_id: session_id, path: path, content: content, **meta
        )
      end

      def create_terminal(session_id:, command:, args: nil, cwd: nil, env: nil, output_byte_limit: nil, **meta)
        request(
          CLIENT_METHODS["terminal_create"], Schema::CreateTerminalRequest, Schema::CreateTerminalResponse,
          session_id: session_id, command: command, args: args, cwd: cwd, env: env,
          output_byte_limit: output_byte_limit, **meta
        )
      end

      def terminal_output(session_id:, terminal_id:, **meta)
        request(
          CLIENT_METHODS["terminal_output"], Schema::TerminalOutputRequest, Schema::TerminalOutputResponse,
          session_id: session_id, terminal_id: terminal_id, **meta
        )
      end

      def release_terminal(session_id:, terminal_id:, **meta)
        request_optional(
          CLIENT_METHODS["terminal_release"], Schema::ReleaseTerminalRequest, Schema::ReleaseTerminalResponse,
          session_id: session_id, terminal_id: terminal_id, **meta
        )
      end

      def wait_for_terminal_exit(session_id:, terminal_id:, **meta)
        request(
          CLIENT_METHODS["terminal_wait_for_exit"], Schema::WaitForTerminalExitRequest,
          Schema::WaitForTerminalExitResponse,
          session_id: session_id, terminal_id: terminal_id, **meta
        )
      end

      def kill_terminal(session_id:, terminal_id:, **meta)
        request_optional(
          CLIENT_METHODS["terminal_kill"], Schema::KillTerminalRequest, Schema::KillTerminalResponse,
          session_id: session_id, terminal_id: terminal_id, **meta
        )
      end

      # Accepts either a full request model/hash or message:+mode: kwargs.
      # Mode is one of ElicitationFormSessionMode / ElicitationFormRequestMode /
      # ElicitationUrlSessionMode / ElicitationUrlRequestMode.
      def create_elicitation(request = nil, message: nil, mode: nil, **meta)
        payload =
          if !message.nil? || !mode.nil?
            raise ArgumentError, "message: and mode: are both required" if message.nil? || mode.nil?
            raise ArgumentError, "request must not be given with message:/mode:" unless request.nil?

            build_elicitation_request(message, mode, meta)
          else
            Schema::CreateElicitationRequest.coerce(request)
          end
        result = @conn.send_request(CLIENT_METHODS["elicitation_create"], payload)
        Schema::CreateElicitationResponse.coerce(result || {})
      end

      def complete_elicitation(elicitation_id:, **meta)
        notify(CLIENT_METHODS["elicitation_complete"], Schema::CompleteElicitationNotification,
               elicitation_id: elicitation_id, **meta)
      end

      def ext_method(name, params = {})
        @conn.send_request("_#{name}", params)
      end

      def ext_notification(name, params = {})
        @conn.send_notification("_#{name}", params)
      end

      private

      def request(method, request_class, response_class, **kwargs)
        payload = build(request_class, kwargs)
        result = @conn.send_request(method, payload)
        response_class.coerce(result || {})
      end

      # Optional responses: null / non-dict responses become nil
      # instead of an empty model.
      def request_optional(method, request_class, response_class, **kwargs)
        payload = build(request_class, kwargs)
        result = @conn.send_request(method, payload)
        return nil unless result.is_a?(Hash)

        response_class.coerce(result)
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

      def build_elicitation_request(message, mode, meta)
        mode_hash = mode.is_a?(Schema::Base) ? mode.to_h : Schema.serialize(mode)
        mode_hash = mode_hash.transform_keys(&:to_s)
        field_meta = meta.delete(:field_meta) || meta.delete(:meta)
        # The mode models carry no "mode" discriminator (it lives on the
        # request), so infer it from the mode class.
        discriminator =
          case mode
          when Schema::ElicitationFormSessionMode, Schema::ElicitationFormRequestMode then "form"
          when Schema::ElicitationUrlSessionMode, Schema::ElicitationUrlRequestMode then "url"
          else mode_hash["mode"]
          end
        # Merge message + mode fields; the CreateElicitationRequest union
        # dispatches to the correct form/url variant.
        hash = { "message" => message }.merge(mode_hash).merge(meta.compact.transform_keys(&:to_s))
        hash["mode"] = discriminator if discriminator
        request = Schema::CreateElicitationRequest.coerce(hash)
        request.field_meta = field_meta if field_meta
        request
      end
    end

    def self.run_agent(agent, input: $stdin, output: $stdout, **connection_options)
      input, output = Stdio.stdio_streams(input, output)
      transport = NdjsonTransport.new(input, output)
      connection = Connection.new(agent, transport, **connection_options)
      Sync { connection.listen }
      connection
    end
  end
end
