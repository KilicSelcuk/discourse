# frozen_string_literal: true

require "demon/base"

module LoadShedder
  class Daemon < ::Demon::Base
    class << self
      attr_accessor :configured_workers
    end

    def self.start(count = 1, verbose: false, logger: nil, workers:)
      self.configured_workers = workers
      super(count, verbose:, logger:)
    end

    def self.prefix
      "load_shedder_adaptive_limiter"
    end

    private

    def after_fork
      worker_count = self.class.configured_workers

      Server.run!(workers_count: worker_count, logger: logger)
    rescue => e
      log("LoadShedderAIMDLimiter exception: #{e} #{e.backtrace.join("\n")}", level: :error)
      raise
    end
  end
end
