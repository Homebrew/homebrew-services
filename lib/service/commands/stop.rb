# frozen_string_literal: true

module Service
  module Commands
    module Stop
      module_function

      def run(target, verbose:)
        ServicesCli.check(target) &&
          ServicesCli.stop(target, verbose: verbose)
      end
    end
  end
end
