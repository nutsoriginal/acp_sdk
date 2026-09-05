# frozen_string_literal: true

require_relative "exceptions"
require_relative "schema_base"

module ACP
  class Route
    attr_reader :method, :kind

    def initialize(method:, handler:, kind:, model: nil, optional: false, default_result: nil, adapt_result: nil)
      @method = method
      @handler = handler
      @kind = kind
      @model = model
      @optional = optional
      @default_result = default_result
      @adapt_result = adapt_result
    end

    def handle(params)
      unless @handler
        return @default_result if @optional

        raise RequestError.method_not_found(@method)
      end

      # Do NOT coerce nil -> {}: missing params must fail validation
      # (invalid_params) instead of being silently replaced.
      # Extension routes handle nil themselves (nil -> {} for wire compat).
      argument = @model ? @model.coerce(params) : params
      result = @handler.call(argument)
      return result unless @kind == :request && @adapt_result

      @adapt_result.call(result)
    end
  end

  class Router
    NORMALIZE_RESULT = ->(result) { result.nil? ? {} : result }

    def initialize
      @requests = {}
      @notifications = {}
      @extension_request = nil
      @extension_notification = nil
    end

    def add_route(route)
      if route.kind == :request
        @requests[route.method] = route
      else
        @notifications[route.method] = route
      end
      route
    end

    def route_request(method, model, target, *names, optional: false, default_result: nil, normalize: false)
      handler = resolve_handler(target, names)
      add_route(Route.new(
                  method: method,
                  handler: handler,
                  kind: :request,
                  model: model,
                  optional: optional,
                  default_result: default_result,
                  adapt_result: normalize ? NORMALIZE_RESULT : nil
                ))
    end

    def route_notification(method, model, target, *names)
      handler = resolve_handler(target, names)
      add_route(Route.new(
                  method: method,
                  handler: handler,
                  kind: :notification,
                  model: model,
                  optional: true
                ))
    end

    def on_extension_request(&block)
      @extension_request = block
    end

    def on_extension_notification(&block)
      @extension_notification = block
    end

    def requests
      @requests.keys
    end

    def notifications
      @notifications.keys
    end

    def call(method, params, is_notification)
      if method.start_with?("_")
        handler = is_notification ? @extension_notification : @extension_request
        return nil if is_notification && handler.nil?
        raise RequestError.method_not_found(method) unless handler

        return handler.call(method[1..], params.is_a?(Hash) ? params : {})
      end

      routes = is_notification ? @notifications : @requests
      route = routes[method]
      raise RequestError.method_not_found(method) unless route

      route.handle(params)
    end

    private

    def resolve_handler(target, names)
      name = names.flatten.find { |candidate| target.respond_to?(candidate) }
      return nil unless name

      target.method(name)
    end
  end
end
