# frozen_string_literal: true
require "rails_helper"
require "load_shedder/aimd_limiter"

RSpec.describe LoadShedder::AIMDLimiter do
  let(:limiter) { described_class.new(initial_limit: 4, target_p95_ms: 300) }

  describe "#admit" do
    it "rejects when over limit" do
      limiter.instance_variable_set(:@limit, 1)

      decision1 = limiter.admit
      decision2 = limiter.admit
      decision3 = limiter.admit

      expect(decision1[:admitted]).to eq(true)
      expect(decision2[:admitted]).to eq(false)
      expect(decision3[:admitted]).to eq(false)
      expect(limiter.inflight).to eq(1)
    end
  end

  describe "#complete" do
    it "backs off on slow samples" do
      limiter.complete(rtt_ms: 1_000)

      expect(limiter.limit).to eq(3)
      expect(limiter.degraded).to eq(1)
    end

    it "increases after a slow cut when saturated and healthy" do
      limiter.instance_variable_set(:@limit, 3)
      limiter.instance_variable_set(:@degraded, 1)

      3.times { limiter.admit } # inflight=3
      limiter.complete(rtt_ms: 50)

      expect(limiter.limit).to eq(4)
      expect(limiter.degraded).to eq(0)
    end

    it "does not change on healthy samples when not saturated" do
      limiter.admit # inflight=1
      limiter.complete(rtt_ms: 50)

      expect(limiter.limit).to eq(4)
      expect(limiter.degraded).to eq(0)
    end

    it "includes anon samples for limit updates" do
      limiter.instance_variable_set(:@limit, 4)
      limiter.admit
      limiter.complete(rtt_ms: 2_000) # slow sample

      expect(limiter.limit).to eq(3)
      expect(limiter.degraded).to eq(1)
    end

    it "respects the minimum limit when backing off" do
      limiter.instance_variable_set(:@limit, 2)
      limiter.complete(rtt_ms: 10_000)

      expect(limiter.limit).to eq(2) # lmin is 2 for initial_limit=4
    end
  end
end
