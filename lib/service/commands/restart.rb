# frozen_string_literal: true

module Service
  module Commands
    module Restart
      module_function

      TRIGGERS = %w[restart relaunch reload r].freeze

      def run(targets, _custom_plist, verbose:)
        return unless ServicesCli.check(targets)

        ran = []
        started = []
        targets.each do |service|
          if service.loaded? && !service.service_file_present?
            ran << service
          else
            # group not-started services with started ones for restart
            started << service
          end
          ServicesCli.stop([service]) if service.loaded?
        end

        ServicesCli.run(ran) unless ran.empty?
        ServicesCli.start(started) unless started.empty?
      end
    end
  end
end
