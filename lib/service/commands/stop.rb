# frozen_string_literal: true

module Service
  module Commands
    module Stop
      module_function

      TRIGGERS = %w[stop unload terminate term t u].freeze

      def run(targets, verbose:, no_wait:)
        ServicesCli.check(targets) &&
          ServicesCli.stop(targets, verbose:, no_wait:)
      end
    end
  end
end
