# typed: true
# frozen_string_literal: true

module Service
  module Commands
    module Stop
      TRIGGERS = %w[stop unload terminate term t u].freeze

      def self.run(targets, verbose:, no_wait:)
        ServicesCli.check(targets) &&
          ServicesCli.stop(targets, verbose:, no_wait:)
      end
    end
  end
end
