# frozen_string_literal: true

module Service
  module Commands
    module Cleanup
      module_function

      def run
        cleaned = []

        cleaned << ServicesCli.kill_orphaned_services
        cleaned << ServicesCli.remove_unused_service_files

        puts "All #{root? ? "root" : "user-space"} services OK, nothing cleaned..." if cleaned.empty?
      end
    end
  end
end
