# frozen_string_literal: true

require "securerandom"
require_relative "../schema"

module ACP
  module Contrib
    # Sentinel for optional parameters. Use `equal?` to test for it; never serialize it.
    UNSET = Object.new.freeze

    class MissingToolCallTitleError < ArgumentError
      def initialize
        super("title must be set before sending a ToolCallStart")
      end
    end

    class UnknownToolCallError < KeyError
      attr_reader :external_id

      def initialize(external_id)
        @external_id = external_id
        super("Unknown tool call id: #{external_id}")
      end
    end

    def self.deep_copy_model(value)
      Marshal.load(Marshal.dump(value))
    end

    def self.copy_model_list(items)
      return nil if items.nil?

      items.map { |item| deep_copy_model(item) }
    end

    # Immutable view of a tracked tool call.
    class TrackedToolCallView
      attr_reader :tool_call_id, :title, :name, :kind, :status,
                  :content, :locations, :raw_input, :raw_output

      def initialize(tool_call_id:, title:, name:, kind:, status:,
                     content:, locations:, raw_input:, raw_output:)
        @tool_call_id = tool_call_id
        @title = title
        @name = name
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
          tool_call_id: @tool_call_id, title: @title, name: @name,
          kind: @kind, status: @status, content: @content,
          locations: @locations, raw_input: @raw_input, raw_output: @raw_output
        }
      end
    end

    class TrackedToolCall
      attr_reader :tool_call_id

      def initialize(tool_call_id:, title: nil, name: nil, kind: nil, status: nil,
                     content: nil, locations: nil, raw_input: nil, raw_output: nil)
        @tool_call_id = tool_call_id
        @title = title
        @name = name
        @kind = kind
        @status = status
        @content = Contrib.copy_model_list(content)
        @locations = Contrib.copy_model_list(locations)
        @raw_input = raw_input
        @raw_output = raw_output
        @stream_buffer = nil
      end

      def to_view
        TrackedToolCallView.new(
          tool_call_id: @tool_call_id,
          title: @title,
          name: @name,
          kind: @kind,
          status: @status,
          content: @content&.map { |item| Contrib.deep_copy_model(item) },
          locations: @locations&.map { |loc| Contrib.deep_copy_model(loc) },
          raw_input: @raw_input,
          raw_output: @raw_output
        )
      end

      def to_tool_call_model
        Schema::ToolCallUpdate.new(
          tool_call_id: @tool_call_id,
          title: @title,
          name: @name,
          kind: @kind,
          status: @status,
          content: Contrib.copy_model_list(@content),
          locations: Contrib.copy_model_list(@locations),
          raw_input: @raw_input,
          raw_output: @raw_output
        )
      end

      def to_start_model
        raise MissingToolCallTitleError if @title.nil?

        Schema::ToolCallStart.new(
          tool_call_id: @tool_call_id,
          title: @title,
          name: @name,
          kind: @kind,
          status: @status,
          content: Contrib.copy_model_list(@content),
          locations: Contrib.copy_model_list(@locations),
          raw_input: @raw_input,
          raw_output: @raw_output
        )
      end

      def update(title: UNSET, name: UNSET, kind: UNSET, status: UNSET,
                 content: UNSET, locations: UNSET, raw_input: UNSET, raw_output: UNSET)
        kwargs = { tool_call_id: @tool_call_id }
        unless title.equal?(UNSET)
          @title = title
          kwargs[:title] = @title
        end
        unless name.equal?(UNSET)
          @name = name
          kwargs[:name] = @name
        end
        unless kind.equal?(UNSET)
          @kind = kind
          kwargs[:kind] = @kind
        end
        unless status.equal?(UNSET)
          @status = status
          kwargs[:status] = @status
        end
        unless content.equal?(UNSET)
          @content = Contrib.copy_model_list(content)
          kwargs[:content] = Contrib.copy_model_list(content)
        end
        unless locations.equal?(UNSET)
          @locations = Contrib.copy_model_list(locations)
          kwargs[:locations] = Contrib.copy_model_list(locations)
        end
        unless raw_input.equal?(UNSET)
          @raw_input = raw_input
          kwargs[:raw_input] = @raw_input
        end
        unless raw_output.equal?(UNSET)
          @raw_output = raw_output
          kwargs[:raw_output] = @raw_output
        end
        Schema::ToolCallProgress.new(**kwargs)
      end

      def append_stream_text(text, title: UNSET, status: UNSET)
        @stream_buffer = "#{@stream_buffer}#{text}"
        content = [Schema::ContentToolCallContent.new(content: Schema::TextContentBlock.new(text: @stream_buffer))]
        update(title: title, status: status, content: content)
      end
    end

    # Utility for generating ACP tool call updates on the agent side.
    class ToolCallTracker
      def initialize(id_factory: nil)
        @id_factory = id_factory || -> { SecureRandom.hex(16) }
        @calls = {}
      end

      def start(external_id, title:, name: nil, kind: nil, status: "in_progress",
                content: nil, locations: nil, raw_input: nil, raw_output: nil)
        state = TrackedToolCall.new(
          tool_call_id: @id_factory.call,
          title: title,
          name: name,
          kind: kind,
          status: status,
          content: content,
          locations: locations,
          raw_input: raw_input,
          raw_output: raw_output
        )
        @calls[external_id] = state
        state.to_start_model
      end

      def progress(external_id, title: UNSET, name: UNSET, kind: UNSET, status: UNSET,
                   content: UNSET, locations: UNSET, raw_input: UNSET, raw_output: UNSET)
        require_call(external_id).update(
          title: title, name: name, kind: kind, status: status,
          content: content, locations: locations,
          raw_input: raw_input, raw_output: raw_output
        )
      end

      def append_stream_text(external_id, text, title: UNSET, status: UNSET)
        require_call(external_id).append_stream_text(text, title: title, status: status)
      end

      def forget(external_id)
        @calls.delete(external_id)
      end

      def tracked?(external_id)
        @calls.key?(external_id)
      end

      def view(external_id)
        require_call(external_id).to_view
      end

      def tool_call_model(external_id)
        require_call(external_id).to_tool_call_model
      end

      private

      def require_call(external_id)
        @calls.fetch(external_id) { raise UnknownToolCallError, external_id }
      end
    end
  end
end
