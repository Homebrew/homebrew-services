# frozen_string_literal: true

module Service
  module Commands
    module Restart
      module_function

      # NOTE: The restart command is used to update service files
      # after a package gets updated through `brew upgrade`.
      # This works by removing the old file with `brew services stop`
      # and installing the new one with `brew services start|run`.

      TRIGGERS = %w[restart relaunch reload r].freeze

      def run(targets, custom_plist, verbose:)
        return unless ServicesCli.check(targets)

        odeprecated "the restart command with a service file" if custom_plist.present?

        ran = []
        started = []
        targets.each do |service|
          if service.loaded? && !service.service_file_present?
            ran << service
          else
            # group not-started services with started ones for restart
            started << service
          end
          ServicesCli.stop([service], verbose: verbose) if service.loaded?
        end

        ServicesCli.run(ran, verbose: verbose) if ran.present?
        ServicesCli.start(started, verbose: verbose) if started.present?
      end
    end
  end
end
