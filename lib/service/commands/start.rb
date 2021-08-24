# frozen_string_literal: true

module Service
  module Commands
    module Start
      module_function

      def run(target, custom_plist, verbose:)
        ServicesCli.check(target) &&
          ServicesCli.start(target, custom_plist, verbose: verbose)
      end
    end
  end
end
