# frozen_string_literal: true

require "json"
require "set"
require "async/queue"
require_relative "exceptions"
require_relative "schema_base"
require_relative "transport"
require_relative "wait"

module ACP
  StreamEvent = Struct.new(:direction, :message, keyword_init: true) do
    def incoming? = direction == :incoming
    def outgoing? = direction == :outgoing
  end

  class Connection
    attr_reader :transport

    def initialize(handler, transport, worker_grace: 0.5)
      @handler = handler
      @transport = transport
      @worker_grace = worker_grace
      @next_id = 0
      @pending = {}
      @closed = false
      @mutex = Mutex.new
      @workers = Set.new
      @observers = []
      @listen_worker = nil
      @notification_queue = ::Async::Queue.new
      @notification_worker = nil
      @finished = Wait::Latch.new
    end

    def closed?
      @closed
    end

    def add_observer(callable = nil, &block)
      observer = callable || block
      raise ArgumentError, "Observer must respond to #call" unless observer.respond_to?(:call)

      @mutex.synchronize { @observers << observer }
      observer
    end

    def remove_observer(observer)
      @mutex.synchronize { @observers.delete(observer) }
    end

    def listen
      start_notification_worker
      receive_loop
    rescue StandardError => e
      ACP.logger.error("acp: receive loop failed: #{e.class}: #{e.message}")
      raise
    ensure
      reject_all(ConnectionError.new("Connection closed"))
      stop_notification_worker
      @finished.open
    end

    def start
      return @listen_worker if listening?

      Wait.ensure_reactor!
      @finished = Wait::Latch.new
      @listen_worker = Wait.spawn("acp-listen") { listen }
    end

    def join(timeout = nil)
      @finished.wait(timeout)
    end

    def send_request(method, params = nil, timeout: nil)
      raise ConnectionError, "Connection closed" if @closed

      request_id = next_id
      promise = Wait::Promise.new
      @mutex.synchronize { @pending[request_id] = promise }

      payload = { "jsonrpc" => "2.0", "id" => request_id, "method" => method }
      payload["params"] = serialize(params) unless params.nil?

      begin
        write(payload)
      rescue StandardError
        @mutex.synchronize { @pending.delete(request_id) }
        raise
      end

      begin
        promise.wait(timeout)
      rescue TimeoutError
        @mutex.synchronize { @pending.delete(request_id) }
        raise TimeoutError, "Request #{method} (id=#{request_id}) timed out after #{timeout}s"
      end
    end

    def send_notification(method, params = nil)
      raise ConnectionError, "Connection closed" if @closed

      payload = { "jsonrpc" => "2.0", "method" => method }
      payload["params"] = serialize(params) unless params.nil?
      write(payload)
    end

    def drain_notifications(timeout: nil)
      return true unless Wait.alive?(@notification_worker)

      latch = Wait::Latch.new
      @notification_queue.push(latch)
      latch.wait(timeout)
    end

    def close
      return if @closed

      @closed = true
      reject_all(ConnectionError.new("Connection closed"))
      begin
        @transport.close
      rescue StandardError => e
        ACP.logger.debug("acp: transport close failed: #{e.message}")
      end
      stop_notification_worker
      stop_workers
    end

    private

    def next_id
      @mutex.synchronize do
        id = @next_id
        @next_id += 1
        id
      end
    end

    def serialize(params)
      Schema.serialize(params)
    end

    def write(payload)
      notify_observers(:outgoing, payload)
      @transport.send_message(payload)
    end

    def receive_loop
      loop do
        break if @closed

        message = begin
          @transport.receive_message
        rescue TimeoutError => e
          ACP.logger.error("acp: #{e.message}")
          break
        rescue ConnectionError => e
          ACP.logger.debug("acp: receive failed: #{e.message}")
          break
        rescue ::Async::Cancel
          break
        end
        break if message.nil?

        notify_observers(:incoming, message)
        process_message(message)
      end
    end

    def process_message(message)
      unless message.is_a?(Hash)
        ACP.logger.warn("acp: ignoring non-object message: #{message.inspect[0, 200]}")
        return
      end

      method = message["method"]
      has_id = message.key?("id")

      if method
        unless method.is_a?(String)
          respond_error(message["id"], RequestError.invalid_request("details" => "method must be a string")) if has_id
          return
        end

        if has_id
          spawn_worker("acp-request:#{method}") { run_request(message) }
        else
          @notification_queue.push(message)
        end
        return
      end

      if has_id
        handle_response(message)
      else
        ACP.logger.warn("acp: ignoring message without method or id: #{message.inspect[0, 200]}")
      end
    end

    def run_request(message)
      payload = { "jsonrpc" => "2.0", "id" => message["id"] }
      begin
        result = @handler.call(message["method"], message["params"], false)
        payload["result"] = serialize(result)
      rescue RequestError => e
        payload["error"] = e.to_error_obj
      rescue Schema::ValidationError => e
        payload["error"] = RequestError.invalid_params(
          "errors" => [{ "message" => e.message, "loc" => e.path }]
        ).to_error_obj
      rescue ::Async::Cancel
        return
      rescue StandardError => e
        ACP.logger.error("acp: handler for #{message['method']} failed: #{e.class}: #{e.message}")
        payload["error"] = RequestError.internal_error("details" => e.message).to_error_obj
      end
      write(payload)
    rescue ConnectionError => e
      ACP.logger.debug("acp: could not send response for #{message['method']}: #{e.message}")
    rescue ::Async::Cancel
      nil
    end

    def respond_error(id, error)
      write({ "jsonrpc" => "2.0", "id" => id, "error" => error.to_error_obj })
    rescue ConnectionError, ::Async::Cancel
      nil
    end

    def run_notification(message)
      @handler.call(message["method"], message["params"], true)
    rescue ::Async::Cancel
      nil
    rescue StandardError => e
      ACP.logger.error("acp: notification handler for #{message['method']} failed: #{e.class}: #{e.message}")
    end

    def handle_response(message)
      promise = @mutex.synchronize { @pending.delete(message["id"]) }
      unless promise
        ACP.logger.debug("acp: response for unknown request id #{message['id'].inspect}")
        return
      end

      if message.key?("error")
        error = message["error"] || {}
        promise.reject(RequestError.new(error["code"] || -32603, error["message"] || "Error", error["data"]))
      else
        promise.resolve(message["result"])
      end
    end

    def reject_all(error)
      pending = @mutex.synchronize do
        items = @pending.values
        @pending.clear
        items
      end
      pending.each { |promise| promise.reject(error) }
    end

    def notify_observers(direction, message)
      observers = @mutex.synchronize { @observers.dup }
      return if observers.empty?

      event = StreamEvent.new(direction: direction, message: message)
      observers.each do |observer|
        observer.call(event)
      rescue StandardError => e
        ACP.logger.error("acp: observer failed: #{e.class}: #{e.message}")
      end
    end

    def start_notification_worker
      return if Wait.alive?(@notification_worker)

      @notification_worker = Wait.spawn("acp-notifications") do
        while (message = @notification_queue.pop)
          if message.is_a?(Wait::Latch)
            message.open
          else
            run_notification(message)
          end
        end
      end
    end

    def stop_notification_worker
      worker = @mutex.synchronize do
        current = @notification_worker
        @notification_worker = nil
        current
      end
      return unless worker

      begin
        @notification_queue.push(nil)
      rescue ::Async::Queue::ClosedError, ClosedQueueError
        nil
      end
      return if Wait.current?(worker)

      Wait.stop(worker) unless Wait.join(worker, @worker_grace)
    end

    def spawn_worker(name, &block)
      Wait.spawn(name) do
        me = Wait.current_worker
        @mutex.synchronize { @workers << me }
        begin
          block.call
        ensure
          @mutex.synchronize { @workers.delete(me) }
        end
      end
    end

    def listening?
      Wait.alive?(@listen_worker)
    end

    def stop_workers
      workers = @mutex.synchronize do
        list = @workers.to_a
        @workers.clear
        list
      end
      workers.each do |worker|
        next if Wait.current?(worker)

        Wait.stop(worker) unless Wait.join(worker, @worker_grace)
      end
      listener = @listen_worker
      return if listener.nil? || Wait.current?(listener)

      Wait.stop(listener) unless Wait.join(listener, @worker_grace)
    end
  end
end
