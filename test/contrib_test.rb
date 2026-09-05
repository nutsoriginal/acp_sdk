# frozen_string_literal: true

require_relative "test_helper"

# Covers contrib helpers: tool call tracking, session accumulation and
# permission brokering, plus deep-copy isolation checks.
class AcpContribTest < Minitest::Test
  S = ACP::Schema
  C = ACP::Contrib

  def notification(session_id, update)
    S::SessionNotification.new(session_id: session_id, update: update)
  end

  # --- tool_calls (mirrors test_contrib_tool_calls.py) ---

  def test_tool_call_tracker_generates_ids_and_updates
    tracker = C::ToolCallTracker.new(id_factory: -> { "generated-id" })
    start = tracker.start("external", title: "Run command", name: "shell")
    assert_equal "generated-id", start.tool_call_id
    assert_equal "shell", start.name

    progress = tracker.progress("external", name: "terminal", status: "completed")
    assert_instance_of S::ToolCallProgress, progress
    assert_equal "generated-id", progress.tool_call_id
    assert_equal "terminal", progress.name

    view = tracker.view("external")
    assert_equal "terminal", view.name
    assert_equal "completed", view.status
  end

  def test_tool_call_tracker_streaming_text_updates_content
    tracker = C::ToolCallTracker.new(id_factory: -> { "stream-id" })
    tracker.start("external", title: "Stream", status: "in_progress")

    update1 = tracker.append_stream_text("external", "hello")
    first = update1.content.first
    assert_instance_of S::ContentToolCallContent, first
    assert_instance_of S::TextContentBlock, first.content
    assert_equal "hello", first.content.text

    update2 = tracker.append_stream_text("external", ", world", status: "in_progress")
    second = update2.content.first
    assert_instance_of S::ContentToolCallContent, second
    assert_equal "hello, world", second.content.text
  end

  def test_tool_call_tracker_unknown_id_raises
    tracker = C::ToolCallTracker.new
    assert_raises(KeyError) { tracker.progress("nope", status: "completed") }
    assert_raises(KeyError) { tracker.view("nope") }
    assert_raises(KeyError) { tracker.tool_call_model("nope") }
    assert_raises(KeyError) { tracker.append_stream_text("nope", "x") }
    error = assert_raises(C::UnknownToolCallError) { tracker.view("nope") }
    assert_equal "nope", error.external_id
  end

  def test_tool_call_tracker_missing_title_raises
    tracker = C::ToolCallTracker.new(id_factory: -> { "t1" })
    assert_raises(ArgumentError) { tracker.start("ext", title: nil) }
  end

  def test_tool_call_tracker_forget_and_tool_call_model
    tracker = C::ToolCallTracker.new(id_factory: -> { "f1" })
    tracker.start("ext", title: "T")
    model = tracker.tool_call_model("ext")
    assert_instance_of S::ToolCallUpdate, model
    assert_equal "f1", model.tool_call_id

    # Returned model is a copy: mutating it does not affect the tracker.
    model.title = "HACKED"
    assert_equal "T", tracker.view("ext").title

    tracker.forget("ext")
    refute tracker.tracked?("ext")
    assert_raises(KeyError) { tracker.view("ext") }
  end

  def test_tool_call_view_is_frozen
    tracker = C::ToolCallTracker.new(id_factory: -> { "v1" })
    tracker.start("ext", title: "T")
    assert tracker.view("ext").frozen?
  end

  def test_tool_call_view_preserves_raw_input_output
    tracker = C::ToolCallTracker.new(id_factory: -> { "r1" })
    tracker.start("ext", title: "T", raw_input: { "cmd" => "ls" }, raw_output: "ok")
    view = tracker.view("ext")
    assert_equal({ "cmd" => "ls" }, view.raw_input)
    assert_equal "ok", view.raw_output

    tracker.progress("ext", raw_input: { "cmd" => "pwd" })
    assert_equal({ "cmd" => "pwd" }, tracker.view("ext").raw_input)
  end

  def test_progress_omitted_fields_stay_unset
    tracker = C::ToolCallTracker.new(id_factory: -> { "u1" })
    tracker.start("ext", title: "T", status: "in_progress")
    progress = tracker.progress("ext", status: "completed")
    assert_equal "completed", progress.status
    assert_equal "u1", progress.tool_call_id
    refute progress.set?(:title)
    # Tracker state keeps the original title.
    assert_equal "T", tracker.view("ext").title
  end

  # --- session_state (mirrors test_contrib_session_state.py) ---

  def test_session_accumulator_merges_tool_calls
    acc = C::SessionAccumulator.new
    acc.apply(notification("s", S::ToolCallStart.new(tool_call_id: "call-1", title: "Read file", status: "in_progress")))
    snapshot = acc.apply(notification("s", S::ToolCallProgress.new(
                                             tool_call_id: "call-1",
                                             status: "completed",
                                             content: [S::ContentToolCallContent.new(content: S::TextContentBlock.new(text: "Done"))]
                                           )))

    tool = snapshot.tool_calls["call-1"]
    assert_equal "completed", tool.status
    assert_equal "Read file", tool.title
    assert_equal "Done", tool.content.first.content.text
  end

  def test_session_accumulator_records_plan_and_mode
    acc = C::SessionAccumulator.new
    acc.apply(notification("s", S::AgentPlanUpdate.new(
                                  entries: [S::PlanEntry.new(content: "Step 1", priority: "medium", status: "pending")]
                                )))
    snapshot = acc.apply(notification("s", S::CurrentModeUpdate.new(current_mode_id: "coding")))
    assert_equal "Step 1", snapshot.plan_entries.first.content
    assert_equal "coding", snapshot.current_mode_id
  end

  def test_session_accumulator_tracks_messages_and_commands
    acc = C::SessionAccumulator.new
    acc.apply(notification("s", S::AvailableCommandsUpdate.new(available_commands: [])))
    acc.apply(notification("s", S::UserMessageChunk.new(content: S::TextContentBlock.new(text: "Hello"))))
    acc.apply(notification("s", S::AgentMessageChunk.new(content: S::TextContentBlock.new(text: "Hi!"))))
    acc.apply(notification("s", S::AgentThoughtChunk.new(content: S::TextContentBlock.new(text: "Hmm"))))

    snapshot = acc.snapshot
    assert_instance_of S::TextContentBlock, snapshot.user_messages.first.content
    assert_instance_of S::TextContentBlock, snapshot.agent_messages.first.content
    assert_equal "Hello", snapshot.user_messages.first.content.text
    assert_equal "Hi!", snapshot.agent_messages.first.content.text
    assert_equal "Hmm", snapshot.agent_thoughts.first.content.text
    assert_equal [], snapshot.available_commands
  end

  def test_session_accumulator_auto_resets_on_new_session
    acc = C::SessionAccumulator.new
    acc.apply(notification("s1", S::ToolCallStart.new(tool_call_id: "call-1", title: "First")))
    acc.apply(notification("s2", S::ToolCallStart.new(tool_call_id: "call-2", title: "Second")))

    snapshot = acc.snapshot
    assert_equal "s2", snapshot.session_id
    refute snapshot.tool_calls.key?("call-1")
    assert snapshot.tool_calls.key?("call-2")
  end

  def test_session_accumulator_rejects_cross_session_when_auto_reset_disabled
    acc = C::SessionAccumulator.new(auto_reset_on_session_change: false)
    acc.apply(notification("s1", S::ToolCallStart.new(tool_call_id: "call-1", title: "First")))
    assert_raises(ArgumentError) do
      acc.apply(notification("s2", S::ToolCallStart.new(tool_call_id: "call-2", title: "Second")))
    end
  end

  def test_session_accumulator_snapshot_before_any_notification_raises
    acc = C::SessionAccumulator.new
    assert_raises(RuntimeError) { acc.snapshot }
  end

  def test_session_accumulator_reset_clears_state
    acc = C::SessionAccumulator.new
    acc.apply(notification("s", S::ToolCallStart.new(tool_call_id: "c", title: "T")))
    acc.reset
    assert_raises(RuntimeError) { acc.snapshot }
    acc.apply(notification("s2", S::UserMessageChunk.new(content: S::TextContentBlock.new(text: "x"))))
    assert_equal "s2", acc.snapshot.session_id
  end

  def test_session_accumulator_subscribe_and_unsubscribe
    acc = C::SessionAccumulator.new
    seen = []
    unsubscribe = acc.subscribe { |snapshot, notif| seen << [snapshot.session_id, notif.session_id] }
    acc.apply(notification("s", S::UserMessageChunk.new(content: S::TextContentBlock.new(text: "x"))))
    assert_equal [%w[s s]], seen
    unsubscribe.call
    acc.apply(notification("s", S::UserMessageChunk.new(content: S::TextContentBlock.new(text: "y"))))
    assert_equal [%w[s s]], seen
  end

  def test_session_accumulator_progress_without_start_creates_state
    acc = C::SessionAccumulator.new
    snapshot = acc.apply(notification("s", S::ToolCallProgress.new(tool_call_id: "late", status: "completed")))
    assert_equal "completed", snapshot.tool_calls["late"].status
  end

  def test_session_accumulator_ignores_unhandled_update_types
    acc = C::SessionAccumulator.new
    acc.apply(notification("s", S::UserMessageChunk.new(content: S::TextContentBlock.new(text: "x"))))
    snapshot = acc.apply(notification("s", S::SessionInfoUpdate.new(title: "t")))
    assert_equal "s", snapshot.session_id
    assert_equal 1, snapshot.user_messages.size
  end

  # --- permissions (mirrors test_contrib_permissions.py) ---

  def test_permission_broker_uses_tracker_state
    captured = {}
    requester = lambda do |request|
      captured[:request] = request
      S::RequestPermissionResponse.new(
        outcome: S::AllowedOutcome.new(option_id: request.options.first.option_id)
      )
    end

    tracker = C::ToolCallTracker.new(id_factory: -> { "perm-id" })
    tracker.start("external", title: "Need approval")
    broker = C::PermissionBroker.new("session", requester, tracker: tracker)

    result = broker.request_for("external", description: "Perform sensitive action")
    assert_instance_of S::AllowedOutcome, result.outcome
    assert_equal captured[:request].options.first.option_id, result.outcome.option_id
    last_content = captured[:request].tool_call.content.last
    assert_instance_of S::ContentToolCallContent, last_content
    assert_instance_of S::TextContentBlock, last_content.content
    assert last_content.content.text.start_with?("Perform sensitive action")
  end

  def test_permission_broker_accepts_custom_options
    tracker = C::ToolCallTracker.new(id_factory: -> { "custom" })
    tracker.start("external", title: "Custom options")
    options = [S::PermissionOption.new(option_id: "allow", name: "Allow once", kind: "allow_once")]
    recorded = []
    requester = lambda do |request|
      recorded << request.options.first.option_id
      S::RequestPermissionResponse.new(
        outcome: S::AllowedOutcome.new(option_id: request.options.first.option_id)
      )
    end

    broker = C::PermissionBroker.new("session", requester, tracker: tracker)
    broker.request_for("external", options: options)
    assert_equal ["allow"], recorded
  end

  def test_default_permission_options_shape
    options = C.default_permission_options
    assert_equal 3, options.size
    assert_equal %w[approve approve_for_session reject].to_set, options.map(&:option_id).to_set
  end

  def test_permission_broker_without_tracker_needs_explicit_tool_call
    requester = ->(_request) { S::RequestPermissionResponse.new(outcome: S::AllowedOutcome.new(option_id: "a")) }
    broker = C::PermissionBroker.new("s", requester)
    assert_raises(C::MissingToolCallError) { broker.request_for("ext") }

    tool_call = S::ToolCallUpdate.new(tool_call_id: "c1")
    response = broker.request_for("ext", tool_call: tool_call)
    assert_instance_of S::AllowedOutcome, response.outcome
  end

  def test_permission_broker_empty_options_raise
    tracker = C::ToolCallTracker.new(id_factory: -> { "e1" })
    tracker.start("ext", title: "T")
    broker = C::PermissionBroker.new("s", ->(_req) { raise "must not be called" }, tracker: tracker)
    assert_raises(C::MissingPermissionOptionsError) { broker.request_for("ext", options: []) }
  end

  def test_permission_broker_does_not_mutate_tracker_state
    tracker = C::ToolCallTracker.new(id_factory: -> { "m1" })
    tracker.start("ext", title: "T")
    seen_title = nil
    requester = lambda do |request|
      seen_title = request.tool_call.title
      request.tool_call.title = "MUTATED"
      S::RequestPermissionResponse.new(outcome: S::AllowedOutcome.new(option_id: "approve"))
    end
    broker = C::PermissionBroker.new("s", requester, tracker: tracker)
    broker.request_for("ext", description: "desc")
    assert_equal "T", seen_title
    assert_equal "T", tracker.view("ext").title
    assert_nil tracker.view("ext").content
  end
end
