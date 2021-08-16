# frozen_string_literal: true

module Service
  module Commands
    module Run
      module_function

      def run(target, verbose:)
        ServicesCli.check(target) &&
          ServicesCli.run(target, verbose: verbose)
      end
    end
  end
end
