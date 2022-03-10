# frozen_string_literal: true

module Service
  module Commands
    module Kill
      module_function

      TRIGGERS = ["kill"].freeze

      def run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.kill(targets, verbose: verbose)
      end
    end
  end
end
