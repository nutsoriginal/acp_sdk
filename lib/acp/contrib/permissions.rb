# frozen_string_literal: true

require_relative "../schema"
require_relative "tool_calls"

module ACP
  module Contrib
    class PermissionBrokerError < StandardError; end

    class MissingToolCallError < PermissionBrokerError
      def initialize
        super("tool_call must be provided when no ToolCallTracker is configured")
      end
    end

    class MissingPermissionOptionsError < PermissionBrokerError
      def initialize
        super("PermissionBroker requires at least one permission option")
      end
    end

    def self.default_permission_options
      [
        Schema::PermissionOption.new(option_id: "approve", name: "Approve", kind: "allow_once"),
        Schema::PermissionOption.new(option_id: "approve_for_session", name: "Approve for session", kind: "allow_always"),
        Schema::PermissionOption.new(option_id: "reject", name: "Reject", kind: "reject_once")
      ]
    end

    # Helper for issuing permission requests tied to tracked tool calls.
    # The requester is a sync callable: response = requester.call(request).
    class PermissionBroker
      def initialize(session_id, requester, tracker: nil, default_options: nil)
        @session_id = session_id
        @requester = requester
        @tracker = tracker
        @default_options = (default_options || Contrib.default_permission_options).map do |option|
          Contrib.deep_copy_model(option)
        end
      end

      def request_for(external_id, description: nil, options: nil, content: nil, tool_call: nil)
        resolved =
          if tool_call.nil?
            raise MissingToolCallError if @tracker.nil?

            @tracker.tool_call_model(external_id)
          else
            Contrib.deep_copy_model(tool_call)
          end

        resolved.content = Contrib.copy_model_list(content) unless content.nil?

        if description
          existing = resolved.content || []
          existing << Schema::ContentToolCallContent.new(
            content: Schema::TextContentBlock.new(text: description)
          )
          resolved.content = existing
        end

        option_set = (options || @default_options).map { |option| Contrib.deep_copy_model(option) }
        raise MissingPermissionOptionsError if option_set.empty?

        request = Schema::RequestPermissionRequest.new(
          session_id: @session_id,
          tool_call: resolved,
          options: option_set
        )
        @requester.call(request)
      end
    end
  end
end
