# frozen_string_literal: true

require_relative "../schema"
require_relative "tool_calls"

module ACP
  module Contrib
    class SessionNotificationMismatchError < ArgumentError
      def initialize(expected, actual)
        super("SessionAccumulator received notification for #{actual}, expected #{expected}")
      end
    end

    class SessionSnapshotUnavailableError < RuntimeError
      def initialize
        super("SessionAccumulator has not processed any notifications yet")
      end
    end

    # Immutable view of a tool call in the session.
    class ToolCallView
      attr_reader :tool_call_id, :title, :kind, :status,
                  :content, :locations, :raw_input, :raw_output

      def initialize(tool_call_id:, title:, kind:, status:,
                     content:, locations:, raw_input:, raw_output:)
        @tool_call_id = tool_call_id
        @title = title
        @kind = kind
        @status = status
        @content = content&.freeze
        @locations = locations&.freeze
        @raw_input = raw_input
        @raw_output = raw_output
        freeze
      end

      def ==(other)
        other.instance_of?(self.class) && to_h == other.to_h
      end

      alias eql? ==

      def hash
        [self.class, to_h].hash
      end

      def to_h
        {
          tool_call_id: @tool_call_id, title: @title, kind: @kind,
          status: @status, content: @content, locations: @locations,
          raw_input: @raw_input, raw_output: @raw_output
        }
      end
    end

    # Aggregated immutable snapshot of the most recent session state.
    class SessionSnapshot
      attr_reader :session_id, :tool_calls, :plan_entries, :current_mode_id,
                  :available_commands, :user_messages, :agent_messages, :agent_thoughts

      def initialize(session_id:, tool_calls:, plan_entries:, current_mode_id:,
                     available_commands:, user_messages:, agent_messages:, agent_thoughts:)
        @session_id = session_id
        @tool_calls = tool_calls.freeze
        @plan_entries = plan_entries.freeze
        @current_mode_id = current_mode_id
        @available_commands = available_commands.freeze
        @user_messages = user_messages.freeze
        @agent_messages = agent_messages.freeze
        @agent_thoughts = agent_thoughts.freeze
        freeze
      end
    end

    class MutableToolCallState
      attr_reader :tool_call_id

      def initialize(tool_call_id)
        @tool_call_id = tool_call_id
        @title = nil
        @kind = nil
        @status = nil
        @content = nil
        @locations = nil
        @raw_input = nil
        @raw_output = nil
      end

      def apply_start(update)
        @title = update.title
        @kind = update.kind
        @status = update.status
        @content = Contrib.copy_model_list(update.content)
        @locations = Contrib.copy_model_list(update.locations)
        @raw_input = update.raw_input
        @raw_output = update.raw_output
      end

      def apply_progress(update)
        @title = update.title unless update.title.nil?
        @kind = update.kind unless update.kind.nil?
        @status = update.status unless update.status.nil?
        @content = Contrib.copy_model_list(update.content) unless update.content.nil?
        @locations = Contrib.copy_model_list(update.locations) unless update.locations.nil?
        @raw_input = update.raw_input unless update.raw_input.nil?
        @raw_output = update.raw_output unless update.raw_output.nil?
      end

      def snapshot
        ToolCallView.new(
          tool_call_id: @tool_call_id,
          title: @title,
          kind: @kind,
          status: @status,
          content: @content&.map { |item| Contrib.deep_copy_model(item) },
          locations: @locations&.map { |loc| Contrib.deep_copy_model(loc) },
          raw_input: @raw_input,
          raw_output: @raw_output
        )
      end
    end

    # Merges SessionNotification objects into a session snapshot.
    # Experimental: APIs may change while feedback is gathered.
    class SessionAccumulator
      attr_reader :session_id

      def initialize(auto_reset_on_session_change: true)
        @auto_reset = auto_reset_on_session_change
        @session_id = nil
        @tool_calls = {}
        @plan_entries = []
        @current_mode_id = nil
        @available_commands = []
        @user_messages = []
        @agent_messages = []
        @agent_thoughts = []
        @subscribers = []
      end

      def reset
        @session_id = nil
        @tool_calls.clear
        @plan_entries.clear
        @current_mode_id = nil
        @available_commands.clear
        @user_messages.clear
        @agent_messages.clear
        @agent_thoughts.clear
      end

      # Registers a callback invoked with (snapshot, notification) after
      # every apply. Returns an unsubscribe lambda.
      def subscribe(&callback)
        @subscribers << callback
        -> { @subscribers.delete(callback) }
      end

      def apply(notification)
        ensure_session(notification)
        apply_update(notification.update)
        snap = snapshot
        @subscribers.dup.each { |callback| callback.call(snap, notification) }
        snap
      end

      def snapshot
        raise SessionSnapshotUnavailableError if @session_id.nil?

        SessionSnapshot.new(
          session_id: @session_id,
          tool_calls: @tool_calls.transform_values(&:snapshot),
          plan_entries: @plan_entries.map { |entry| Contrib.deep_copy_model(entry) },
          current_mode_id: @current_mode_id,
          available_commands: @available_commands.map { |command| Contrib.deep_copy_model(command) },
          user_messages: @user_messages.map { |message| Contrib.deep_copy_model(message) },
          agent_messages: @agent_messages.map { |message| Contrib.deep_copy_model(message) },
          agent_thoughts: @agent_thoughts.map { |message| Contrib.deep_copy_model(message) }
        )
      end

      private

      def ensure_session(notification)
        if @session_id.nil?
          @session_id = notification.session_id
          return
        end
        handle_session_change(notification.session_id) if notification.session_id != @session_id
      end

      def handle_session_change(session_id)
        if @session_id.nil?
          @session_id = session_id
          return
        end
        raise SessionNotificationMismatchError.new(@session_id, session_id) unless @auto_reset

        reset
        @session_id = session_id
      end

      def apply_update(update)
        case update
        when Schema::ToolCallStart
          state_for(update.tool_call_id).apply_start(update)
        when Schema::ToolCallProgress
          state_for(update.tool_call_id).apply_progress(update)
        when Schema::AgentPlanUpdate
          @plan_entries = Contrib.copy_model_list(update.entries) || []
        when Schema::CurrentModeUpdate
          @current_mode_id = update.current_mode_id
        when Schema::AvailableCommandsUpdate
          @available_commands = Contrib.copy_model_list(update.available_commands) || []
        when Schema::UserMessageChunk
          @user_messages << Contrib.deep_copy_model(update)
        when Schema::AgentMessageChunk
          @agent_messages << Contrib.deep_copy_model(update)
        when Schema::AgentThoughtChunk
          @agent_thoughts << Contrib.deep_copy_model(update)
        end
      end

      def state_for(tool_call_id)
        @tool_calls[tool_call_id] ||= MutableToolCallState.new(tool_call_id)
      end
    end
  end
end
