# frozen_string_literal: true

module Service
  module Commands
    module Start
      module_function

      TRIGGERS = %w[start launch load s l].freeze

      def run(targets, custom_plist, verbose:)
        ServicesCli.check(targets) &&
          ServicesCli.start(targets, custom_plist, verbose: verbose)
      end
    end
  end
end
