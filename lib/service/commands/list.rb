# frozen_string_literal: true

module Service
  module Commands
    module List
      module_function

      def run
        ServicesCli.list
      end
    end
  end
end
