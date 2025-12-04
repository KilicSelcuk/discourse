# frozen_string_literal: true

require "socket"

module LoadShedder
  class Client
    DEFAULT_SOCKET_PATH = LoadShedder::Server::SOCKET_PATH

    def initialize(socket_path: DEFAULT_SOCKET_PATH)
      @socket_path = socket_path
      @socket = nil
    end

    def admit(_kind = nil)
      with_socket do |socket|
        socket.write("ADMIT kind=anon\n")
        parse_admit(socket.gets&.strip)
      end
    end

    def complete(status:, rtt_ms:)
      with_socket do |socket|
        socket.write("COMPLETE rtt_ms=#{rtt_ms.to_i} status=#{status}\n")
        socket.gets
        nil
      end
    end

    private

    def parse_admit(line)
      unless line
        return { admitted: true, limit: nil, inflight: nil, degraded: 0, contacted: false }
      end

      tokens = line.split(" ")
      status = tokens.shift
      kv = tokens.to_h { |part| part.split("=", 2) }
      {
        admitted: status == "OK",
        limit: kv["limit"]&.to_i,
        inflight: kv["inflight"]&.to_i,
        degraded: kv["degraded"]&.to_i,
        contacted: true,
      }
    end

    def with_socket
      socket = ensure_socket
      yield socket
    rescue Errno::EPIPE, Errno::ECONNRESET, IOError => e
      close_socket
      raise e
    end

    def ensure_socket
      return @socket if @socket&.closed? == false

      close_socket
      @socket = UNIXSocket.new(@socket_path)
    end

    def close_socket
      @socket&.close
      @socket = nil
    end
  end
end
