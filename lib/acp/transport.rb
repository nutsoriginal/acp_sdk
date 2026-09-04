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
      if @receive_timeout && @input.respond_to?(:wait_readable) && !@input.wait_readable(@receive_timeout)
        raise TimeoutError, "No message received within #{@receive_timeout}s"
      end

      @input.gets
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
      @closed = false
    end

    def closed?
      @closed
    end

    def send_message(message)
      raise ConnectionError, "Transport is closed" if @closed

      @outbox.push(JSON.parse(JSON.generate(message)))
    end

    def receive_message
      return nil if @closed && @inbox.empty?

      @inbox.pop
    end

    def close
      return if @closed

      @closed = true
      @outbox.push(nil)
      @inbox.push(nil)
    end
  end
end
