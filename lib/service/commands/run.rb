# frozen_string_literal: true

module Service
  module Commands
    module Run
      module_function

      TRIGGERS = ["run"].freeze

      def run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.run(targets, verbose:)
      end
    end
  end
end
