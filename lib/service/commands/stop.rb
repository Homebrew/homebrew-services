# frozen_string_literal: true

module Service
  module Commands
    module Stop
      module_function

      TRIGGERS = %w[stop unload terminate term t u].freeze

      def run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.stop(targets, verbose: verbose)
      end
    end
  end
end
