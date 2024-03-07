# frozen_string_literal: true

module Service
  module Commands
    module Kill
      module_function

      TRIGGERS = %w[kill k].freeze

      def run(targets, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.kill(targets, verbose:)
      end
    end
  end
end
