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

      worker.stop
    rescue ::Async::Cancel, StandardError
      nil
    end

    def self.join(worker, timeout = nil)
      return true if worker.nil? || worker.finished?

      if timeout.nil?
        worker.wait
      else
        worker.wait(timeout: timeout)
      end
      true
    rescue ::Async::Cancel
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

      def settled?
        @promise.resolved?
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
