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

    # Parity with the reference 50MB stdio buffer: inbound lines are
    # reassembled in bounded chunks and a line beyond the cap is skipped,
    # so a rogue peer cannot exhaust memory via stdout. (The reference
    # accepts such lines; we deliberately reject them instead.)
    DEFAULT_MAX_LINE_BYTES = 50 * 1024 * 1024
    READ_CHUNK_BYTES = 64 * 1024

    attr_reader :input, :output

    def initialize(input, output, receive_timeout: nil, max_line_bytes: DEFAULT_MAX_LINE_BYTES)
      @input = input
      @output = output
      @receive_timeout = receive_timeout
      @max_line_bytes = max_line_bytes
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
        begin
          line = read_line
        rescue LineTooLongError => e
          ACP.logger.warn("acp: skipping over-long line: #{e.message}")
          next
        end
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
      return read_line_chunks unless @receive_timeout

      if Wait.async?
        begin
          ::Async::Task.current.with_timeout(@receive_timeout) { read_line_chunks }
        rescue ::Async::TimeoutError
          raise TimeoutError, "No message received within #{@receive_timeout}s"
        end
      elsif @input.respond_to?(:wait_readable)
        raise TimeoutError, "No message received within #{@receive_timeout}s" unless @input.wait_readable(@receive_timeout)

        read_line_chunks
      else
        raise TimeoutError, "No message received within #{@receive_timeout}s" unless IO.select([@input], nil, nil, @receive_timeout)

        read_line_chunks
      end
    end

    # Reads one "\n"-terminated line in bounded chunks so a giant line never
    # sits in memory twice. Returns nil on EOF (or the trailing partial line,
    # like a short read). Raises LineTooLongError after discarding the rest
    # of an over-long line to keep framing in sync.
    def read_line_chunks
      buffer = nil
      loop do
        chunk = @input.gets("\n", READ_CHUNK_BYTES)
        if chunk.nil?
          return nil if buffer.nil? || buffer.empty?

          return buffer
        end
        buffer = chunk.dup.clear if buffer.nil?
        buffer << chunk
        if buffer.bytesize > @max_line_bytes
          discard_line_rest(chunk)
          raise LineTooLongError, "line exceeds #{@max_line_bytes} bytes"
        end
        return buffer if chunk.end_with?("\n")
      end
    end

    def discard_line_rest(last_chunk)
      return if last_chunk.end_with?("\n")

      loop do
        chunk = @input.gets("\n", READ_CHUNK_BYTES)
        return if chunk.nil? || chunk.end_with?("\n")
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
