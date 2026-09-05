# frozen_string_literal: true

require_relative "transport"
require_relative "client"
require_relative "wait"

module ACP
  module Stdio
    DEFAULT_INHERITED_ENV = %w[HOME LOGNAME PATH SHELL TERM USER].freeze

    def self.default_environment
      env = {}
      DEFAULT_INHERITED_ENV.each do |key|
        value = ENV.fetch(key, nil)
        next if value.nil? || value.start_with?("()")

        env[key] = value
      end
      env
    end

    def self.stdio_streams(input = $stdin, output = $stdout)
      input.binmode if input.respond_to?(:binmode)
      output.binmode if output.respond_to?(:binmode)
      input.set_encoding("UTF-8") if input.respond_to?(:set_encoding)
      output.set_encoding("UTF-8") if output.respond_to?(:set_encoding)
      output.sync = true if output.respond_to?(:sync=)
      [input, output]
    end

    def self.spawn_agent(command, *args, env: nil, cwd: nil, stderr: :log, receive_timeout: nil)
      merged = default_environment
      merged.merge!(env.transform_keys(&:to_s)) if env

      reader, writer = IO.pipe
      child_reader, child_writer = IO.pipe
      stderr_reader, stderr_writer = stderr == :log ? IO.pipe : [nil, nil]

      options = { in: child_reader, out: writer }
      options[:chdir] = cwd.to_s if cwd
      options[:err] = case stderr
                      when :log then stderr_writer
                      when :inherit then $stderr
                      when :discard then File::NULL
                      when IO then stderr
                      else raise ArgumentError, "Unsupported stderr option: #{stderr.inspect}"
                      end

      pid = Process.spawn(merged, command, *args, **options)
      child_reader.close
      writer.close
      stderr_writer&.close

      reader.set_encoding("UTF-8")
      child_writer.set_encoding("UTF-8")
      child_writer.sync = true

      drain = stderr_reader ? start_stderr_drain(stderr_reader, "#{File.basename(command)}[#{pid}]") : nil

      transport = NdjsonTransport.new(reader, child_writer, receive_timeout: receive_timeout)
      AgentProcess.new(pid: pid, transport: transport, stdin: child_writer, stdout: reader, stderr_drain: drain)
    end

    def self.start_stderr_drain(io, label)
      io.set_encoding("UTF-8")
      Wait.spawn("acp-stderr-#{label}") do
        io.each_line do |line|
          line = line.scrub unless line.valid_encoding?
          ACP.logger.info("acp[#{label}] stderr: #{line.chomp}")
        end
      rescue IOError, Errno::EBADF, Wait::TASK_STOPPED
        nil
      ensure
        io.close unless io.closed?
      end
    end

    class AgentProcess
      attr_reader :pid, :transport

      def initialize(pid:, transport:, stdin:, stdout:, stderr_drain: nil)
        @pid = pid
        @transport = transport
        @stdin = stdin
        @stdout = stdout
        @stderr_drain = stderr_drain
        @status = nil
      end

      def connect(client_handler, start_listening: true, **options)
        connection = Client::Connection.new(client_handler, @transport, **options)
        connection.start if start_listening
        connection
      end

      def alive?
        return false if @status

        Process.kill(0, @pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      def wait
        return @status if @status

        _, status = Process.wait2(@pid)
        @status = status
      rescue Errno::ECHILD
        @status
      end

      def kill(signal = "TERM")
        Process.kill(signal, @pid)
      rescue Errno::ESRCH
        nil
      end

      def close(timeout: 2.0)
        @stdin.close unless @stdin.closed?
        @transport.close
        return finish if wait_with_timeout(timeout)

        kill
        return finish if wait_with_timeout(timeout)

        kill("KILL")
        wait
        finish
      rescue StandardError
        nil
      end

      private

      def finish
        Wait.join(@stderr_drain, 1.0)
        @status
      end

      def wait_with_timeout(timeout)
        return true if @status

        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        loop do
          _, status = Process.wait2(@pid, Process::WNOHANG)
          if status
            @status = status
            return true
          end

          return false if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

          sleep 0.02
        end
      rescue Errno::ECHILD
        true
      end
    end
  end
end
