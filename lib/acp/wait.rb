# frozen_string_literal: true

require "async"
require "async/promise"
require "logger"
require_relative "exceptions"

module ACP
  def self.logger
    @logger ||= Logger.new($stderr, progname: "acp").tap { |logger| logger.level = Logger::WARN }
  end

  def self.logger=(value)
    @logger = value
  end

  module Wait
    # Task cancellation exception renamed across async 2.x:
    # older releases raise Async::Stop, newer raise Async::Cancel
    # (with Stop kept as an alias). Pick whichever exists.
    TASK_STOPPED =
      if defined?(::Async::Cancel)
        ::Async::Cancel
      elsif defined?(::Async::Stop)
        ::Async::Stop
      else
        StandardError
      end

    def self.async?
      !::Async::Task.current?.nil?
    rescue RuntimeError
      false
    end

    def self.ensure_reactor!
      return if async?

      raise Error, "ACP must run inside an Async reactor; wrap your code in Sync { ... }"
    end

    def self.spawn(name = nil, &block)
      ensure_reactor!
      Async(annotation: name, &block)
    end

    def self.alive?(worker)
      return false if worker.nil?

      worker.alive? && !worker.finished?
    end

    def self.current_worker
      ::Async::Task.current
    end

    def self.current?(worker)
      return false if worker.nil?

      worker == ::Async::Task.current?
    end

    def self.stop(worker)
      return if worker.nil? || worker.finished?

      if worker.respond_to?(:stop)
        worker.stop
      else
        worker.cancel
      end
    rescue TASK_STOPPED, StandardError
      nil
    end

    def self.join(worker, timeout = nil)
      return true if worker.nil? || worker.finished?

      if timeout.nil?
        worker.wait
      elsif async?
        # Task#wait(timeout:) only exists on newer async; with_timeout
        # around a blocking wait works on every 2.x.
        begin
          ::Async::Task.current.with_timeout(timeout) { worker.wait }
        rescue ::Async::TimeoutError
          return false
        end
      else
        require "timeout" unless defined?(::Timeout)
        begin
          ::Timeout.timeout(timeout) { worker.wait }
        rescue ::Timeout::Error
          return false
        end
      end
      true
    rescue TASK_STOPPED
      true
    rescue ::Async::TimeoutError, TimeoutError
      false
    rescue StandardError
      worker.finished? || !alive?(worker)
    end

    class Latch
      def initialize
        @promise = ::Async::Promise.new
      end

      def open?
        @promise.completed?
      end

      def open
        @promise.resolve(true)
      end

      def wait(timeout = nil)
        if timeout.nil?
          @promise.wait
        else
          @promise.wait(timeout: timeout)
        end
        true
      rescue ::Async::TimeoutError
        false
      end
    end

    class Promise
      def initialize
        @promise = ::Async::Promise.new
      end

      # Async::Promise#resolved? is true after either resolve or reject
      # (completed? is only true for successful resolution), so it is the
      # correct settled check. Fall back to failed?/completed? for safety.
      def settled?
        @promise.resolved? || @promise.failed? || @promise.completed?
      end

      def resolve(value)
        @promise.resolve(value)
      end

      def reject(error)
        @promise.reject(error)
      end

      def wait(timeout = nil)
        if timeout.nil?
          @promise.wait
        else
          @promise.wait(timeout: timeout)
        end
      rescue ::Async::TimeoutError
        raise TimeoutError, "Timed out after #{timeout}s"
      end
    end
  end
end
