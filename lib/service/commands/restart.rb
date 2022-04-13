# frozen_string_literal: true

module Service
  module Commands
    module Restart
      module_function

      TRIGGERS = %w[restart relaunch reload r].freeze

      def run(targets, custom_plist, verbose:)
        return unless ServicesCli.check(targets)

        odeprecated "the restart command with a service file" if custom_plist.present?

        start_targets = []

        targets.each do |service|
          unless service.loaded?
            start_targets << service
            next
          end

          if ServicesCli.service_restart(service)
            ohai "Successfully restarted `#{service.name}` (label: #{service.service_name})"
          else
            opoo "Unable to restart `#{service.name}` (label: #{service.service_name})"
          end
        end

        ServicesCli.start(start_targets, verbose: verbose) if start_targets.present?
      end
    end
  end
end
