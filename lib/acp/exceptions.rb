# frozen_string_literal: true

module ACP
  class Error < StandardError; end

  class RequestError < Error
    attr_reader :code, :data

    def initialize(code, message, data = nil)
      super(message)
      @code = code
      @data = data
    end

    def self.parse_error(data = nil) = new(-32700, "Parse error", data)
    def self.invalid_request(data = nil) = new(-32600, "Invalid request", data)
    def self.method_not_found(method) = new(-32601, "Method not found", { "method" => method })
    def self.invalid_params(data = nil) = new(-32602, "Invalid params", data)
    def self.internal_error(data = nil) = new(-32603, "Internal error", data)
    def self.request_cancelled(data = nil) = new(-32800, "Request cancelled", data)
    def self.auth_required(data = nil) = new(-32000, "Authentication required", data)
    def self.resource_not_found(uri = nil) = new(-32002, "Resource not found", uri ? { "uri" => uri } : nil)

    def to_error_obj
      { "code" => @code, "message" => message, "data" => @data }
    end
  end

  class ConnectionError < Error; end

  class TimeoutError < Error; end
end
