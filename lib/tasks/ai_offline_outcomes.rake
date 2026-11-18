# frozen_string_literal: true

namespace :ai do
  namespace :outcomes do
    desc "Opt-in bounded, offline document producer/worker (no AI API, no Send)"
    task run: :environment do
      abort "Offline outcome scheduler disabled. No work performed." unless
        ENV["AI_OFFLINE_OUTCOME_SCHEDULER_ENABLED"] == "1"

      scan = AiWorkspace::OutcomeTriggerProducer.new.scan_once!(limit: 50)
      worker = AiWorkspace::AutomationOutcomeWorker.new
      processed = 0
      10.times do
        break unless worker.process_one!
        processed += 1
      end
      puts "offline outcomes: scanned=#{scan.scanned} enqueued=#{scan.enqueued} processed=#{processed}"
    end
  end
end
