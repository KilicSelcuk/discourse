# frozen_string_literal: true

module LoadShedder
  class Middleware
    RETRY_AFTER_SECONDS = 2
    WARN_INTERVAL_SECONDS = 60

    def initialize(app, client: nil)
      @app = app
      @client = client || LoadShedder::Client.new
    end

    def call(env)
      unless GlobalSetting.respond_to?(:load_shedder_enabled) && GlobalSetting.load_shedder_enabled
        return @app.call(env)
      end

      request = Rack::Request.new(env)
      kind = logged_in?(env) ? "user" : "anon"
      start_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      decision = admit
      admitted = kind == "user" ? true : decision[:admitted]

      unless admitted
        headers = busy_headers(decision)
        return 503, headers, [I18n.t("load_shedder.server_busy")]
      end

      status = nil
      headers = nil
      body = nil
      begin
        status, headers, body = @app.call(env)
      rescue => e
        headers ||= {}
        status ||= 500
        raise e
      ensure
        headers ||= {}
        status ||= 500
        attach_headers(headers, decision)
        if decision[:contacted]
          rtt_ms = extract_rtt_ms(headers, start_mono)
          complete(status, rtt_ms)
        end
      end

      [status, headers, body]
    rescue => e
      rate_limited_warn("LoadShedder error: #{e}")
      raise
    end

    private

    def admit
      @client.admit
    rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE, IOError, SystemCallError => e
      rate_limited_warn("LoadShedder admit failed: #{e}")
      { admitted: true, limit: nil, inflight: nil, degraded: 0, contacted: false }
    end

    def complete(status, rtt_ms)
      @client.complete(status: status, rtt_ms: rtt_ms)
    rescue Errno::ENOENT, Errno::ECONNREFUSED, Errno::EPIPE, IOError, SystemCallError => e
      rate_limited_warn("LoadShedder complete failed: #{e}")
    end

    def extract_rtt_ms(headers, start_mono)
      if runtime = headers["X-Runtime"]
        (runtime.to_f * 1000).round
      else
        ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_mono) * 1000).round
      end
    end

    def busy_headers(decision)
      {
        "Content-Type" => "text/plain",
        "Retry-After" => RETRY_AFTER_SECONDS.to_s,
        "X-AC-Limit" => decision[:limit]&.to_s,
        "X-AC-Inflight" => decision[:inflight]&.to_s,
        "X-AC-Degraded" => decision[:degraded]&.to_s,
      }.compact
    end

    def attach_headers(headers, decision)
      headers["X-AC-Limit"] = decision[:limit].to_s if decision[:limit]
      headers["X-AC-Inflight"] = decision[:inflight].to_s if decision[:inflight]
      headers["X-AC-Degraded"] = decision[:degraded].to_s if decision[:degraded]
    end

    def logged_in?(env)
      Auth::DefaultCurrentUserProvider.find_v1_auth_cookie(env).present?
    rescue => e
      rate_limited_warn("LoadShedder auth check failed: #{e}")
      false
    end

    def rate_limited_warn(message)
      key = :"load_shedder_warned_at"
      now = Time.now.to_i
      last = Thread.current.thread_variable_get(key)
      return if last && now - last < WARN_INTERVAL_SECONDS

      Thread.current.thread_variable_set(key, now)
      Rails.logger.warn(message)
    end
  end
end
