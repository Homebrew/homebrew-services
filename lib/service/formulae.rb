# frozen_string_literal: true

module Service
  module Formulae
    module_function

    # All available services
    # @private
    def available_services
      require "formula"

      Formula.installed.map { |formula| FormulaWrapper.new(formula) }.select(&:plist?).sort_by(&:name)
    end

    # List all available services with status, user, and path to the file.
    def services_list
      available_services.map do |service|
        formula = {
          name:   service.formula.name,
          status: :stopped,
          user:   nil,
          file:   nil,
        }

        if service.service_file_present?(for: :root) && service.pid?
          formula[:user] = "root"
          formula[:file] = System.boot_path + service.service_file.basename
        elsif service.service_file_present?(for: :user) && service.pid?
          formula[:user] = System.user_of_process(service.pid)
          formula[:file] = System.user_path + service.service_file.basename
        elsif service.loaded?
          formula[:user] = System.user
          formula[:file] = service.service_file
        end

        # If we have a file or a user defined, check if the service is running or errored.
        if formula[:user] && formula[:file]
          formula[:status] =
            Service::ServicesCli.service_get_operational_status(service)
        end

        formula
      end
    end
  end
end
