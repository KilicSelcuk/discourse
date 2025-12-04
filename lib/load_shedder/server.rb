# frozen_string_literal: true

require "fileutils"
require "socket"

module LoadShedder
  class Server
    SOCKET_PATH = "#{Rails.root}/tmp/sockets/load_shedder.sock"

    def self.run!(workers_count:, logger:)
      limiter =
        AIMDLimiter.new(
          initial_limit: workers_count,
          target_p95_ms: GlobalSetting.load_shedder_target_p95_ms,
        )
      new(limiter: limiter, logger: logger, workers_count: workers_count).run
    ensure
      limiter&.stop
    end

    def initialize(limiter:, logger:, workers_count:)
      @limiter = limiter
      @logger = logger
      @workers_count = workers_count
      prepare_socket_path
      @server = UNIXServer.new(SOCKET_PATH)
      @pool = Scheduler::ThreadPool.new(min_threads: 0, max_threads: @workers_count)
    end

    def run
      loop do
        client = @server.accept
        @pool.post { handle_client(client) }
      end
    ensure
      stop
    end

    def stop
      @server&.close
      @pool&.shutdown
      begin
        @pool&.wait_for_termination(timeout: 1)
      rescue Scheduler::ThreadPool::ShutdownError
        # best-effort shutdown
      end
      FileUtils.rm_f(SOCKET_PATH)
    end

    private

    def prepare_socket_path
      FileUtils.mkdir_p(File.dirname(SOCKET_PATH))
      FileUtils.rm_f(SOCKET_PATH)
    end

    def process_line(line)
      command, rest = line.split(" ", 2)
      params = parse_params(rest)

      case command
      when "ADMIT"
        admit(params["kind"])
      when "COMPLETE"
        complete(params)
      when "STATS"
        stats
      else
        "ERR unknown\n"
      end
    end

    def admit(_kind_param)
      decision = @limiter.admit
      status = decision[:admitted] ? "OK" : "REJECT"
      format_stats(status, decision[:limit], decision[:inflight], decision[:degraded])
    end

    def complete(params)
      rtt_ms = (params["rtt_ms"] || 0).to_f

      @limiter.complete(rtt_ms: rtt_ms, sample: true, time: Time.now)
      "OK\n"
    end

    def stats
      current = @limiter.stats
      format_stats(nil, current[:limit], current[:inflight], current[:degraded])
    end

    def format_stats(status, limit, inflight, degraded)
      prefix = status ? "#{status} " : ""
      "#{prefix}limit=#{limit} inflight=#{inflight} degraded=#{degraded}\n"
    end

    def parse_params(parts)
      return {} unless parts

      parts.split(" ").to_h { |part| part.split("=", 2) }
    end

    def handle_client(client)
      while (line = client.gets)
        response = process_line(line.strip)
        client.write(response)
      end
    rescue => e
      @logger.warn("LoadShedder server error: #{e}")
    ensure
      client&.close
    end
  end
end
