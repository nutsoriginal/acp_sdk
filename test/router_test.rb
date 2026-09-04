# frozen_string_literal: true

require_relative "test_helper"

class AcpRouterTest < Minitest::Test
  S = ACP::Schema

  class Target
    attr_reader :seen

    def initialize
      @seen = []
    end

    def prompt(request)
      @seen << request
      S::PromptResponse.new(stop_reason: "end_turn")
    end

    def set_session_mode(request)
      @seen << request
      nil
    end

    def cancel(notification)
      @seen << notification
    end
  end

  def test_route_dispatch_with_raw_handler
    router = ACP::Router.new
    router.add_route(ACP::Route.new(
      method: "echo",
      handler: ->(params) { { "text" => params["text"] } },
      kind: :request
    ))

    result = router.call("echo", { "text" => "hi" }, false)
    assert_equal "hi", result["text"]
  end

  def test_route_request_validates_params_into_model
    target = Target.new
    router = ACP::Router.new
    router.route_request("session/prompt", S::PromptRequest, target, :prompt)

    result = router.call("session/prompt", { "sessionId" => "s", "prompt" => [{ "type" => "text", "text" => "hi" }] }, false)
    assert_instance_of S::PromptResponse, result
    assert_instance_of S::PromptRequest, target.seen.first
    assert_equal "hi", target.seen.first.prompt.first.text

    assert_raises(S::ValidationError) { router.call("session/prompt", { "prompt" => [] }, false) }
  end

  def test_normalize_turns_nil_result_into_empty_hash
    target = Target.new
    router = ACP::Router.new
    router.route_request("session/set_mode", S::SetSessionModeRequest, target, :set_session_mode, normalize: true)

    assert_equal({}, router.call("session/set_mode", { "sessionId" => "s", "modeId" => "m" }, false))
  end

  def test_notification_route
    target = Target.new
    router = ACP::Router.new
    router.route_notification("session/cancel", S::CancelNotification, target, :cancel)

    router.call("session/cancel", { "sessionId" => "s" }, true)
    assert_equal "s", target.seen.first.session_id
  end

  def test_missing_handler_is_method_not_found_unless_optional
    router = ACP::Router.new
    router.route_request("required", S::PromptRequest, Object.new, :nope)
    router.route_request("optional", S::PromptRequest, Object.new, :nope, optional: true, default_result: {})

    error = assert_raises(ACP::RequestError) { router.call("required", {}, false) }
    assert_equal(-32601, error.code)
    assert_equal({}, router.call("optional", nil, false))
  end

  def test_method_not_found
    router = ACP::Router.new
    error = assert_raises(ACP::RequestError) { router.call("missing", nil, false) }
    assert_equal(-32601, error.code)
  end

  def test_extension_methods
    router = ACP::Router.new
    router.on_extension_request { |name, params| { "ext" => name, "params" => params } }

    assert_equal({ "ext" => "custom", "params" => {} }, router.call("_custom", nil, false))
    assert_nil router.call("_custom", {}, true)
    router.on_extension_notification { |name, _params| raise "seen #{name}" }
    assert_raises(RuntimeError) { router.call("_custom", {}, true) }
  end
end
