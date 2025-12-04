# frozen_string_literal: true

module LoadShedder
  # AIMDLimiter implements a simple AIMD controller inspired by Netflix's
  # concurrency-limits. It adjusts the allowed inflight requests based on
  # request latency (slow => multiplicative cut, healthy under load => additive
  # increase). Reference:
  # https://github.com/Netflix/concurrency-limits/blob/26e9fca4b0341355cbfc4fa7e9911b812a794583/concurrency-limits-core/src/main/java/com/netflix/concurrency/limits/limit/AIMDLimit.java
  class AimdLimiter
    ADDITIVE_STEP = 1
    MULTIPLICATIVE_DECREASE = 0.9

    attr_reader :limit, :inflight, :degraded

    def initialize(
      initial_limit:,
      target_p95_ms:,
      additive_step: ADDITIVE_STEP,
      multiplicative_decrease: MULTIPLICATIVE_DECREASE
    )
      @mutex = Mutex.new
      @initial_limit = [initial_limit.to_i, 1].max
      @target_p95_ms = target_p95_ms.to_i
      @additive_step = additive_step
      @multiplicative_decrease = multiplicative_decrease

      @limit = @initial_limit
      @inflight = 0
      @degraded = 0
    end

    def admit
      @mutex.synchronize do
        admitted = @inflight < @limit
        @inflight += 1 if admitted
        decision_hash(admitted)
      end
    end

    def complete(rtt_ms:, sample: true, time: Time.now)
      @mutex.synchronize do
        @inflight -= 1 if @inflight.positive?
        return unless sample

        slow = rtt_ms.to_f > @target_p95_ms
        update_limit(slow:)
      end
    end

    def stats
      @mutex.synchronize { { limit: @limit, inflight: @inflight, degraded: @degraded } }
    end

    private

    def update_limit(slow:)
      if slow
        @limit = [lmin, (@limit * @multiplicative_decrease).floor].max
        @degraded = 1
      elsif (@inflight * 2) >= @limit
        @limit = [lmax, @limit + @additive_step].min
        @degraded = 0
      else
        @degraded = 0
      end
    end

    def lmin
      [1, (@initial_limit * 0.5).floor].max
    end

    def lmax
      @initial_limit
    end

    def decision_hash(admitted)
      { admitted: admitted, limit: @limit, inflight: @inflight, degraded: @degraded }
    end
  end

  AIMDLimiter = AimdLimiter
end
