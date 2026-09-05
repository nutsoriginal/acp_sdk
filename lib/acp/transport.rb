# frozen_string_literal: true

require "json"
require "async/queue"
require_relative "exceptions"

module ACP
  def self.memory_transport_pair
    MemoryTransport.pair
  end

  module Transport
    def send_message(_message)
      raise NotImplementedError
    end

    def receive_message
      raise NotImplementedError
    end

    def close
      raise NotImplementedError
    end
  end

  class NdjsonTransport
    include Transport

    attr_reader :input, :output

    def initialize(input, output, receive_timeout: nil)
      @input = input
      @output = output
      @receive_timeout = receive_timeout
      @write_mutex = Mutex.new
      @closed = false
      @output.sync = true if @output.respond_to?(:sync=)
    end

    def closed?
      @closed
    end

    def send_message(message)
      line = JSON.generate(message)
      @write_mutex.synchronize do
        raise ConnectionError, "Transport is closed" if @closed

        @output.write("#{line}\n")
        @output.flush if @output.respond_to?(:flush)
      end
    rescue IOError, Errno::EPIPE, Errno::EBADF => e
      raise ConnectionError, "Failed to write message: #{e.message}"
    end

    def receive_message
      loop do
        line = read_line
        return nil if line.nil?

        line = line.scrub unless line.valid_encoding?
        stripped = line.strip
        next if stripped.empty?

        begin
          return JSON.parse(stripped)
        rescue JSON::ParserError => e
          ACP.logger.warn("acp: skipping malformed JSON line: #{e.message}")
        end
      end
    rescue IOError, Errno::EBADF
      nil
    end

    def close
      @write_mutex.synchronize { @closed = true }
      [@input, @output].each do |io|
        io.close unless io.nil? || io.closed?
      rescue IOError, Errno::EBADF
        nil
      end
    end

    private

    def read_line
      return @input.gets unless @receive_timeout

      if Wait.async?
        begin
          ::Async::Task.current.with_timeout(@receive_timeout) { @input.gets }
        rescue ::Async::TimeoutError
          raise TimeoutError, "No message received within #{@receive_timeout}s"
        end
      elsif @input.respond_to?(:wait_readable)
        raise TimeoutError, "No message received within #{@receive_timeout}s" unless @input.wait_readable(@receive_timeout)

        @input.gets
      else
        raise TimeoutError, "No message received within #{@receive_timeout}s" unless IO.select([@input], nil, nil, @receive_timeout)

        @input.gets
      end
    end
  end

  class MemoryTransport
    include Transport

    def self.pair
      a_to_b = ::Async::Queue.new
      b_to_a = ::Async::Queue.new
      [new(b_to_a, a_to_b), new(a_to_b, b_to_a)]
    end

    def initialize(inbox, outbox)
      @inbox = inbox
      @outbox = outbox
      @mutex = Mutex.new
      @closed = false
    end

    def closed?
      @mutex.synchronize { @closed }
    end

    def send_message(message)
      raise ConnectionError, "Transport is closed" if closed?

      # JSON round-trip simulates the wire: isolates mutation between peers
      # and normalizes symbol keys to strings, like NDJSON framing does.
      @outbox.push(JSON.parse(JSON.generate(message)))
    rescue ::Async::Queue::ClosedError
      raise ConnectionError, "Transport is closed"
    end

    def receive_message
      return nil if closed? && @inbox.empty?

      @inbox.pop
    end

    def close
      should_signal = @mutex.synchronize do
        next false if @closed

        @closed = true
        true
      end
      return unless should_signal

      # Signal EOF to the peer only. The local receive loop unblocks via
      # task cancellation (Connection#stop_workers) or via the closed?+empty?
      # fast path in receive_message above. Pushing nil to our own inbox
      # would discard ordering guarantees, so we deliberately avoid it.
      begin
        @outbox.push(nil)
      rescue ::Async::Queue::ClosedError
        nil
      end
    end
  end
end
