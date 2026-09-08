# frozen_string_literal: true

require_relative "test_helper"

class AcpTransportTest < Minitest::Test
  def setup
    @previous_logger = ACP.logger
    ACP.logger = Logger.new(File::NULL)
  end

  def teardown
    ACP.logger = @previous_logger
  end

  def test_ndjson_roundtrip
    reader_io, writer_io = IO.pipe
    reader_io.set_encoding("UTF-8")
    writer_io.set_encoding("UTF-8")

    transport = ACP::NdjsonTransport.new(reader_io, writer_io)
    transport.send_message({ "jsonrpc" => "2.0", "method" => "test", "params" => { "text" => "привет" } })

    message = transport.receive_message
    assert_equal "test", message["method"]
    assert_equal "привет", message["params"]["text"]
    transport.close
  end

  def test_ndjson_skips_blank_and_malformed_lines
    reader_io, writer_io = IO.pipe
    writer_io.write("\n")
    writer_io.write("not json at all\n")
    writer_io.write("{\"ok\": true}\n")
    writer_io.close

    transport = ACP::NdjsonTransport.new(reader_io, StringIO.new)
    assert_equal({ "ok" => true }, transport.receive_message)
    assert_nil transport.receive_message
    transport.close
  end

  def test_ndjson_receive_timeout
    reader_io, writer_io = IO.pipe
    transport = ACP::NdjsonTransport.new(reader_io, writer_io, receive_timeout: 0.05)
    assert_raises(ACP::TimeoutError) { transport.receive_message }
    transport.close
  end

  def test_ndjson_write_after_close_raises_connection_error
    reader_io, writer_io = IO.pipe
    transport = ACP::NdjsonTransport.new(reader_io, writer_io)
    transport.close
    assert_raises(ACP::ConnectionError) { transport.send_message({ "a" => 1 }) }
  end

  def test_ndjson_reassembles_lines_bigger_than_read_chunk
    reader_io, writer_io = IO.pipe
    reader_io.set_encoding("UTF-8")
    writer_io.set_encoding("UTF-8")

    # 300KB of multibyte text: spans several 64KB chunks and splits
    # multibyte characters across chunk boundaries. Sending runs in a
    # child task: the payload exceeds the pipe buffer, so a sequential
    # write would deadlock before the reader starts draining.
    big = "привет" * 50_000
    transport = ACP::NdjsonTransport.new(reader_io, writer_io)
    sender = Async { transport.send_message({ "text" => big }) }

    message = transport.receive_message
    sender.wait
    assert_equal big, message["text"]
    transport.close
  end

  def test_ndjson_default_max_line_is_50mb
    assert_equal 50 * 1024 * 1024, ACP::NdjsonTransport::DEFAULT_MAX_LINE_BYTES
    transport = ACP::NdjsonTransport.new(StringIO.new, StringIO.new)
    assert_equal 50 * 1024 * 1024, transport.instance_variable_get(:@max_line_bytes)
    transport.close
  end

  def test_ndjson_skips_overlong_line_and_resyncs
    log = StringIO.new
    ACP.logger = Logger.new(log)

    reader_io, writer_io = IO.pipe
    writer_io.write("#{'x' * 200}\n")
    writer_io.write("{\"ok\": true}\n")
    writer_io.close

    transport = ACP::NdjsonTransport.new(reader_io, StringIO.new, max_line_bytes: 100)
    assert_equal({ "ok" => true }, transport.receive_message)
    assert_match(/over-long/, log.string)
    transport.close
  end

  def test_ndjson_overlong_line_at_eof_is_skipped
    reader_io, writer_io = IO.pipe
    writer_io.write("y" * 200)
    writer_io.close

    transport = ACP::NdjsonTransport.new(reader_io, StringIO.new, max_line_bytes: 100)
    assert_nil transport.receive_message
    transport.close
  end

  def test_memory_transport_pair
    left, right = ACP.memory_transport_pair
    left.send_message({ "hello" => "world", sym: :value })
    message = right.receive_message
    assert_equal "world", message["hello"]
    assert_equal "value", message["sym"]
    left.close
    right.close
  end

  def test_memory_transport_close_signals_eof_to_both_sides
    left, right = ACP.memory_transport_pair
    left.close
    assert_nil right.receive_message
    assert_nil left.receive_message
    assert_raises(ACP::ConnectionError) { left.send_message({}) }
  end
end
